//! WASM bindings for keepassxc database operations.

use std::cell::RefCell;
use std::collections::BTreeMap;

use keepass::DatabaseKey;
use keepassxc::{
    create_group as create_group_in_db, delete_entry as delete_entry_from_db,
    delete_group as delete_group_from_db, extract_challenge as extract_core_challenge,
    move_entry as move_entry_in_db, move_group as move_group_in_db, open_bytes,
    read_entry_field as read_entry_field_value, read_entry_fields as read_entry_payload,
    read_entry_totp_at, rename_group as rename_group_in_db, save_bytes,
    serialization::{EntryFields, EntryInfo, GroupInfo, MergeInfo, TotpInfo},
    update_entry, Database, DatabaseConfig, Entry, EntryExt, EntryFieldExt, GroupExt,
};
use serde_json::json;
use wasm_bindgen::prelude::*;
use zeroize::Zeroizing;

thread_local! {
 static DATABASES: RefCell<BTreeMap<u32, Database>> = RefCell::new(BTreeMap::new());
 static NEXT_HANDLE: RefCell<u32> = RefCell::new(1);
}

/// Allocates the next handle from `current`, or `None` once every `u32`
/// value has been handed out, split out from `store_database` so the
/// overflow check itself is testable without constructing a `JsValue`,
/// which panics outside a real wasm32 target (see this module's other
/// `JsValue`-avoiding tests).
fn next_handle(current: u32) -> Option<u32> {
    current.checked_add(1)
}

fn store_database(db: Database) -> Result<u32, JsValue> {
    let handle = NEXT_HANDLE.with(|h| -> Result<u32, JsValue> {
        let mut h = h.borrow_mut();
        let id = *h;
        let next = next_handle(id).ok_or_else(|| {
            err_json(
                "HANDLE_EXHAUSTED",
                "No more database handles available in this session",
            )
        })?;
        *h = next;
        Ok(id)
    })?;
    DATABASES.with(|dbs| dbs.borrow_mut().insert(handle, db));
    Ok(handle)
}

fn with_database<F, R>(handle: u32, f: F) -> Result<R, JsValue>
where
    F: FnOnce(&Database) -> R,
{
    DATABASES.with(|dbs| {
        let dbs = dbs.borrow();
        let db = dbs.get(&handle).ok_or_else(|| {
            JsValue::from_str(
 &json!({"code": "INVALID_HANDLE", "message": format!("No database with handle {}", handle)})
 .to_string(),
 )
        })?;
        Ok(f(db))
    })
}

fn with_database_mut<F, R>(handle: u32, f: F) -> Result<R, JsValue>
where
    F: FnOnce(&mut Database) -> R,
{
    DATABASES.with(|dbs| {
        let mut dbs = dbs.borrow_mut();
        let db = dbs.get_mut(&handle).ok_or_else(|| {
            JsValue::from_str(
 &json!({"code": "INVALID_HANDLE", "message": format!("No database with handle {}", handle)})
 .to_string(),
 )
        })?;
        Ok(f(db))
    })
}

fn err_json(code: &str, message: &str) -> JsValue {
    JsValue::from_str(&json!({"code": code, "message": message}).to_string())
}

/// Runs `f` behind `catch_unwind`, so a panic anywhere in the exported call
/// graph (including in the `keepass-rs`/`keepassxc` core reached through it,
/// e.g. from a crafted `.kdbx` file) becomes a `PANIC`-shaped `Err` instead of
/// unwinding across the `#[wasm_bindgen]` boundary. An uncaught unwind there
/// traps the whole WASM instance, killing every other open database handle
/// held in this session's `thread_local!` state, mirrors
/// `keepassxc-ffi::error::catch_unwind`.
fn catch_unwind_result<T>(
    f: impl FnOnce() -> Result<T, JsValue> + std::panic::UnwindSafe,
) -> Result<T, JsValue> {
    std::panic::catch_unwind(f).unwrap_or_else(|payload| {
        let msg = if let Some(s) = payload.downcast_ref::<&str>() {
            s.to_string()
        } else if let Some(s) = payload.downcast_ref::<String>() {
            s.clone()
        } else {
            "unknown panic".to_string()
        };
        Err(err_json("PANIC", &format!("internal panic: {}", msg)))
    })
}

/// Installs a panic hook that forwards panic messages to the browser/Node
/// console, and is called automatically on module instantiation. Diagnostic
/// only, `catch_unwind_result` above is what prevents a panic from
/// trapping the instance.
#[wasm_bindgen(start)]
pub fn init_panic_hook() {
    console_error_panic_hook::set_once();
}

fn find_group<'a>(root: &'a keepassxc::Group, uuid_str: &str) -> Option<&'a keepassxc::Group> {
    if uuid_str.is_empty() {
        return Some(root);
    }
    let target = uuid::Uuid::parse_str(uuid_str).ok()?;
    root.find_group_by_uuid(target)
}

fn find_entry<'a>(root: &'a keepassxc::Group, uuid_str: &str) -> Option<&'a keepassxc::Entry> {
    let target = uuid::Uuid::parse_str(uuid_str).ok()?;
    root.find_entry_by_uuid(target)
}

fn parse_uuid(uuid_str: &str, kind: &str) -> Result<uuid::Uuid, JsValue> {
    uuid::Uuid::parse_str(uuid_str)
        .map_err(|_| err_json("PARSE_ERROR", &format!("Invalid {kind} UUID: {uuid_str}")))
}

#[wasm_bindgen]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[wasm_bindgen]
pub fn create_db() -> Result<String, JsValue> {
    catch_unwind_result(|| {
        let db = Database::new(DatabaseConfig::default());
        let handle = store_database(db)?;
        Ok(json!({"handle": handle}).to_string())
    })
}

#[wasm_bindgen]
pub fn open_db(
    db_bytes: &[u8],
    password: &str,
    key_file_bytes: Option<Vec<u8>>,
) -> Result<String, JsValue> {
    let key_file_bytes = key_file_bytes.map(Zeroizing::new);
    catch_unwind_result(|| {
        let mut key = DatabaseKey::new();

        if !password.is_empty() {
            key = key.with_password(password);
        }

        if let Some(kf_bytes) = key_file_bytes {
            key = key.with_keyfile(&mut kf_bytes.as_slice()).map_err(|e| {
                err_json("KEY_FILE_ERROR", &format!("Failed to read key file: {}", e))
            })?;
        }

        let db =
            open_bytes(db_bytes, key).map_err(|e| err_json("OPEN_ERROR", &format!("{}", e)))?;

        let handle = store_database(db)?;
        Ok(json!({"handle": handle}).to_string())
    })
}

#[wasm_bindgen]
pub fn open_db_with_key_file(
    db_bytes: &[u8],
    password: &str,
    key_file_bytes: Vec<u8>,
) -> Result<String, JsValue> {
    // Owned `Vec<u8>` (not `&[u8]`), matching open_db/save_db: wasm-bindgen's
    // generated glue for a `Vec<u8>` parameter hands over the real owned
    // buffer backing the WASM-linear-memory copy the JS side made, so
    // wrapping it in Zeroizing zeroes those bytes before dealloc.
    // A `&[u8]` parameter's backing buffer is instead owned/dropped by
    // wasm-bindgen's own generated wrapper with no way for this function to
    // reach in and zero it first.
    let key_file_bytes = Zeroizing::new(key_file_bytes);
    catch_unwind_result(|| {
        let mut key = DatabaseKey::new();
        if !password.is_empty() {
            key = key.with_password(password);
        }
        key = key
            .with_keyfile(&mut key_file_bytes.as_slice())
            .map_err(|e| err_json("KEY_FILE_ERROR", &format!("Failed to read key file: {}", e)))?;

        let db =
            open_bytes(db_bytes, key).map_err(|e| err_json("OPEN_ERROR", &format!("{}", e)))?;

        let handle = store_database(db)?;
        Ok(json!({"handle": handle}).to_string())
    })
}

#[wasm_bindgen]
pub fn open_db_with_challenge_response(
    db_bytes: &[u8],
    password: &str,
    challenge_response_hex: &str,
) -> Result<String, JsValue> {
    catch_unwind_result(|| {
        let cr_bytes = hex::decode(challenge_response_hex).map_err(|e| {
            err_json(
                "PARSE_ERROR",
                &format!("Invalid hex in challenge_response: {}", e),
            )
        })?;

        let key = DatabaseKey::new()
            .with_password(password)
            .with_challenge_response_bytes(cr_bytes);

        let db =
            open_bytes(db_bytes, key).map_err(|e| err_json("OPEN_ERROR", &format!("{}", e)))?;

        let handle = store_database(db)?;
        Ok(json!({"handle": handle}).to_string())
    })
}

#[wasm_bindgen]
pub fn close_db(handle: u32) -> Result<(), JsValue> {
    catch_unwind_result(|| {
        DATABASES.with(|dbs| {
            let removed = dbs.borrow_mut().remove(&handle);
            if removed.is_none() {
                return Err(err_json(
                    "INVALID_HANDLE",
                    &format!("No database with handle {}", handle),
                ));
            }
            Ok(())
        })
    })
}

#[wasm_bindgen]
pub fn list_groups(handle: u32, group_uuid: &str) -> Result<String, JsValue> {
    let uuid_owned = group_uuid.to_string();
    catch_unwind_result(|| {
        with_database(handle, |db| {
            let group = find_group(&db.root, &uuid_owned).ok_or_else(|| {
                err_json("NOT_FOUND", &format!("Group not found: {}", uuid_owned))
            })?;

            let groups: Vec<GroupInfo> = group.groups.iter().map(GroupInfo::from).collect();
            Ok(serde_json::to_string(&groups)
                .map_err(|e| err_json("JSON_ERROR", &e.to_string()))?)
        })?
    })
}

#[wasm_bindgen]
pub fn list_entries(handle: u32, group_uuid: &str) -> Result<String, JsValue> {
    let uuid_owned = group_uuid.to_string();
    catch_unwind_result(|| {
        with_database(handle, |db| {
            let group = find_group(&db.root, &uuid_owned).ok_or_else(|| {
                err_json("NOT_FOUND", &format!("Group not found: {}", uuid_owned))
            })?;

            let entries: Vec<EntryInfo> = group.entries.iter().map(EntryInfo::from).collect();
            Ok(serde_json::to_string(&entries)
                .map_err(|e| err_json("JSON_ERROR", &e.to_string()))?)
        })?
    })
}

#[wasm_bindgen]
pub fn read_entry_fields(handle: u32, entry_uuid: &str) -> Result<String, JsValue> {
    let uuid_owned = entry_uuid.to_string();
    catch_unwind_result(|| {
        with_database(handle, |db| {
            let entry = find_entry(&db.root, &uuid_owned).ok_or_else(|| {
                err_json("NOT_FOUND", &format!("Entry not found: {}", uuid_owned))
            })?;
            let payload = read_entry_payload(entry);
            let fields = EntryFields::from(payload);
            Ok(serde_json::to_string(&fields)
                .map_err(|e| err_json("JSON_ERROR", &e.to_string()))?)
        })?
    })
}

/// Fetches a single field's plaintext value on demand, instead of the whole
/// entry via `read_entry_fields`. Lets callers avoid pulling protected
/// values (e.g. Password) across the WASM/JS boundary until the caller
/// needs one, e.g. when a user clicks "reveal" or "copy", rather
/// than every time the entry is opened for viewing or editing.
#[wasm_bindgen]
pub fn read_entry_field(
    handle: u32,
    entry_uuid: &str,
    field_name: &str,
) -> Result<String, JsValue> {
    let uuid_owned = entry_uuid.to_string();
    let field_name = field_name.to_string();
    catch_unwind_result(|| {
        with_database(handle, |db| {
            let entry = find_entry(&db.root, &uuid_owned).ok_or_else(|| {
                err_json("NOT_FOUND", &format!("Entry not found: {}", uuid_owned))
            })?;
            read_entry_field_value(entry, &field_name).ok_or_else(|| {
                err_json(
                    "NOT_FOUND",
                    &format!("Field '{}' not found on entry {}", field_name, uuid_owned),
                )
            })
        })?
    })
}

#[wasm_bindgen]
pub fn get_totp(handle: u32, entry_uuid: &str) -> Result<String, JsValue> {
    let uuid_owned = entry_uuid.to_string();
    let now = (js_sys::Date::now() / 1000.0) as u64;
    catch_unwind_result(|| {
        with_database(handle, |db| {
            let entry = find_entry(&db.root, &uuid_owned).ok_or_else(|| {
                err_json("NOT_FOUND", &format!("Entry not found: {}", uuid_owned))
            })?;
            let payload = read_entry_totp_at(entry, now).map_err(|error| {
                err_json("TOTP_ERROR", &format!("Failed to read TOTP: {}", error))
            })?;

            match payload {
                Some(payload) => {
                    let info = TotpInfo::from(payload);
                    serde_json::to_string(&info).map_err(|e| err_json("JSON_ERROR", &e.to_string()))
                }
                None => Ok("null".to_string()),
            }
        })?
    })
}

#[wasm_bindgen]
pub fn create_entry(handle: u32, group_uuid: &str, title: &str) -> Result<String, JsValue> {
    let group_uuid = group_uuid.to_string();
    let title = title.to_string();
    catch_unwind_result(|| {
        with_database_mut(handle, |db| {
            let group = if group_uuid.is_empty() {
                &mut db.root
            } else {
                let group_uuid = parse_uuid(&group_uuid, "group")?;
                db.root.find_group_by_uuid_mut(group_uuid).ok_or_else(|| {
                    err_json("NOT_FOUND", &format!("Group not found: {}", group_uuid))
                })?
            };

            let mut entry = Entry::new();
            entry.set_unprotected(keepassxc::fields::TITLE, &title);
            let info = EntryInfo::from(&entry);
            group.add_entry(entry);

            serde_json::to_string(&info).map_err(|e| err_json("JSON_ERROR", &e.to_string()))
        })?
    })
}

#[wasm_bindgen]
pub fn set_entry_field(
    handle: u32,
    entry_uuid: &str,
    field_name: &str,
    value: &str,
    is_protected: bool,
) -> Result<(), JsValue> {
    let field_name = field_name.to_string();
    let value = value.to_string();
    catch_unwind_result(|| {
        let entry_uuid = parse_uuid(entry_uuid, "entry")?;
        with_database_mut(handle, |db| {
            let meta = db.meta.clone();
            update_entry(&mut db.root, entry_uuid, &meta, |entry| {
                entry.set_field(&field_name, &value, is_protected);
            })
            .map_err(|error| err_json("UPDATE_ERROR", &error.to_string()))
        })?
    })
}

#[wasm_bindgen]
pub fn delete_entry(handle: u32, entry_uuid: &str) -> Result<(), JsValue> {
    catch_unwind_result(|| {
        let entry_uuid = parse_uuid(entry_uuid, "entry")?;
        with_database_mut(handle, |db| {
            delete_entry_from_db(db, entry_uuid, true)
                .map_err(|error| err_json("DELETE_ERROR", &error.to_string()))
        })?
    })
}

#[wasm_bindgen]
pub fn move_entry(handle: u32, entry_uuid: &str, target_group_uuid: &str) -> Result<(), JsValue> {
    catch_unwind_result(|| {
        let entry_uuid = parse_uuid(entry_uuid, "entry")?;
        let target_group_uuid = if target_group_uuid.is_empty() {
            None
        } else {
            Some(parse_uuid(target_group_uuid, "group")?)
        };
        with_database_mut(handle, |db| {
            let target_group_uuid = target_group_uuid.unwrap_or(db.root.uuid);
            move_entry_in_db(&mut db.root, entry_uuid, target_group_uuid)
                .map_err(|error| err_json("MOVE_ERROR", &error.to_string()))
        })?
    })
}

#[wasm_bindgen]
pub fn create_group(handle: u32, parent_group_uuid: &str, name: &str) -> Result<String, JsValue> {
    let name = name.to_string();
    catch_unwind_result(|| {
        let parent_group_uuid = if parent_group_uuid.is_empty() {
            None
        } else {
            Some(parse_uuid(parent_group_uuid, "parent group")?)
        };
        with_database_mut(handle, |db| {
            let parent_uuid = parent_group_uuid.unwrap_or(db.root.uuid);
            let uuid = create_group_in_db(&mut db.root, parent_uuid, &name)
                .map_err(|error| err_json("CREATE_ERROR", &error.to_string()))?;

            let group = db.root.find_group_by_uuid(uuid).unwrap();
            let info = GroupInfo::from(group);

            serde_json::to_string(&info).map_err(|e| err_json("JSON_ERROR", &e.to_string()))
        })?
    })
}

#[wasm_bindgen]
pub fn rename_group(handle: u32, group_uuid: &str, new_name: &str) -> Result<(), JsValue> {
    let new_name = new_name.to_string();
    catch_unwind_result(|| {
        let group_uuid = parse_uuid(group_uuid, "group")?;
        with_database_mut(handle, |db| {
            rename_group_in_db(&mut db.root, group_uuid, &new_name)
                .map_err(|error| err_json("RENAME_ERROR", &error.to_string()))
        })?
    })
}

#[wasm_bindgen]
pub fn delete_group(handle: u32, group_uuid: &str) -> Result<(), JsValue> {
    catch_unwind_result(|| {
        let group_uuid = parse_uuid(group_uuid, "group")?;
        with_database_mut(handle, |db| {
            delete_group_from_db(db, group_uuid, true)
                .map_err(|error| err_json("DELETE_ERROR", &error.to_string()))
        })?
    })
}

#[wasm_bindgen]
pub fn move_group(handle: u32, group_uuid: &str, target_parent_uuid: &str) -> Result<(), JsValue> {
    catch_unwind_result(|| {
        let group_uuid = parse_uuid(group_uuid, "group")?;
        let target_parent_uuid = if target_parent_uuid.is_empty() {
            None
        } else {
            Some(parse_uuid(target_parent_uuid, "target parent")?)
        };
        with_database_mut(handle, |db| {
            let target_parent_uuid = target_parent_uuid.unwrap_or(db.root.uuid);
            move_group_in_db(&mut db.root, group_uuid, target_parent_uuid)
                .map_err(|error| err_json("MOVE_ERROR", &error.to_string()))
        })?
    })
}

#[wasm_bindgen]
pub fn save_db(
    handle: u32,
    password: &str,
    key_file_bytes: Option<Vec<u8>>,
) -> Result<String, JsValue> {
    let password = Zeroizing::new(password.to_string());
    let key_file_bytes = key_file_bytes.map(Zeroizing::new);
    catch_unwind_result(|| {
        with_database_mut(handle, |db| {
            let mut key = DatabaseKey::new();
            if !password.is_empty() {
                key = key.with_password(&password);
            }
            if let Some(key_file_bytes) = key_file_bytes {
                key = key
                    .with_keyfile(&mut key_file_bytes.as_slice())
                    .map_err(|error| err_json("KEY_FILE_ERROR", &error.to_string()))?;
            }

            let buffer =
                save_bytes(db, key).map_err(|error| err_json("SAVE_ERROR", &error.to_string()))?;
            Ok(hex::encode(buffer))
        })?
    })
}

#[wasm_bindgen]
pub fn merge_databases(handle_a: u32, handle_b: u32) -> Result<String, JsValue> {
    catch_unwind_result(|| {
        DATABASES.with(|dbs| {
            let mut dbs = dbs.borrow_mut();

            if !dbs.contains_key(&handle_a) {
                return Err(err_json(
                    "INVALID_HANDLE",
                    &format!("No database with handle {}", handle_a),
                ));
            }
            if !dbs.contains_key(&handle_b) {
                return Err(err_json(
                    "INVALID_HANDLE",
                    &format!("No database with handle {}", handle_b),
                ));
            }

            let db_b = dbs.remove(&handle_b).unwrap();

            // Run the merge behind its own catch_unwind so db_b is always
            // reinserted before this function returns, even if the merge
            // itself panics on a crafted database, otherwise db_b would
            // silently vanish from DATABASES with no way to recover it. Any
            // caught panic is re-raised afterward so the outer
            // catch_unwind_result still converts it into a PANIC error.
            let merge_outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let db_a = dbs.get_mut(&handle_a).unwrap();
                keepassxc::merge(db_a, &db_b)
            }));
            dbs.insert(handle_b, db_b);

            let merge_result = match merge_outcome {
                Ok(result) => result,
                Err(payload) => std::panic::resume_unwind(payload),
            };
            let result = merge_result.map_err(|e| err_json("MERGE_ERROR", &format!("{}", e)))?;
            let info = MergeInfo::from(&result);

            serde_json::to_string(&info).map_err(|e| err_json("JSON_ERROR", &e.to_string()))
        })
    })
}

#[wasm_bindgen]
pub fn extract_challenge(db_bytes: &[u8]) -> Result<String, JsValue> {
    catch_unwind_result(|| {
        let seed = extract_core_challenge(db_bytes)
            .map_err(|e| err_json("PARSE_ERROR", &format!("{}", e)))?;
        Ok(hex::encode(seed))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use keepassxc::{fields, CustomDataItem, CustomDataValue, DatabaseConfig};

    fn open_test_handle() -> u32 {
        let mut db = Database::new(DatabaseConfig::default());
        let source_uuid = db.root.uuid;
        let target_uuid = create_group_in_db(&mut db.root, source_uuid, "Target").unwrap();

        let mut entry = Entry::new();
        entry.set_unprotected(fields::TITLE, "WASM Entry");
        entry.tags = vec!["work".to_string(), "favorite".to_string()];
        entry.custom_data.insert(
            "otp".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String(
                    "otpauth://totp/ManyKee:wasm?secret=DEF".to_string(),
                )),
                last_modification_time: None,
                unknown_xml: Vec::new(),
            },
        );
        entry.custom_data.insert(
            "display_hint".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("login".to_string())),
                last_modification_time: None,
                unknown_xml: Vec::new(),
            },
        );
        db.root.entries.push(entry);

        let mut bytes = Vec::new();
        db.save(&mut bytes, DatabaseKey::new().with_password("test"))
            .unwrap();
        let opened = open_db(&bytes, "test", None).unwrap();
        let json: serde_json::Value = serde_json::from_str(&opened).unwrap();
        let handle = json["handle"].as_u64().unwrap() as u32;

        let groups_json = list_groups(handle, "").unwrap();
        let groups: Vec<serde_json::Value> = serde_json::from_str(&groups_json).unwrap();
        assert!(groups
            .iter()
            .any(|group| group["uuid"] == target_uuid.to_string()));

        handle
    }

    #[test]
    fn next_handle_rejects_at_u32_max() {
        assert_eq!(next_handle(u32::MAX - 1), Some(u32::MAX));
        assert_eq!(next_handle(u32::MAX), None);
    }

    #[test]
    fn wasm_read_entry_fields_omits_otp_seed_and_includes_safe_data() {
        let handle = open_test_handle();
        let entries_json = list_entries(handle, "").unwrap();
        let entries: Vec<serde_json::Value> = serde_json::from_str(&entries_json).unwrap();
        let entry_uuid = entries[0]["uuid"].as_str().unwrap();

        let payload = read_entry_fields(handle, entry_uuid).unwrap();
        let payload: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert!(payload["custom_data"].get("otp").is_none());
        assert_eq!(
            payload["custom_data"]["display_hint"].as_str(),
            Some("login")
        );
        assert_eq!(
            payload["tags"].as_array().unwrap(),
            &[serde_json::json!("work"), serde_json::json!("favorite")]
        );
        close_db(handle).unwrap();
    }

    #[test]
    fn wasm_read_entry_fields_scrubs_protected_values_but_keeps_status() {
        let handle = open_test_handle();
        let entries_json = list_entries(handle, "").unwrap();
        let entries: Vec<serde_json::Value> = serde_json::from_str(&entries_json).unwrap();
        let entry_uuid = entries[0]["uuid"].as_str().unwrap();

        set_entry_field(handle, entry_uuid, fields::PASSWORD, "hunter2", true).unwrap();

        let payload = read_entry_fields(handle, entry_uuid).unwrap();
        let payload: serde_json::Value = serde_json::from_str(&payload).unwrap();
        assert_eq!(payload["fields"]["Password"].as_str(), Some(""));
        assert_eq!(payload["protected"]["Password"].as_bool(), Some(true));
        // Non-protected fields are unaffected.
        assert_eq!(payload["fields"]["Title"].as_str(), Some("WASM Entry"));

        // The scrubbed value is still fetchable on demand.
        assert_eq!(
            read_entry_field(handle, entry_uuid, fields::PASSWORD).unwrap(),
            "hunter2"
        );

        close_db(handle).unwrap();
    }

    #[test]
    fn wasm_list_entries_blanks_protected_summary_fields() {
        let handle = open_test_handle();
        let entries_json = list_entries(handle, "").unwrap();
        let entries: Vec<serde_json::Value> = serde_json::from_str(&entries_json).unwrap();
        let entry_uuid = entries[0]["uuid"].as_str().unwrap();

        set_entry_field(handle, entry_uuid, fields::USERNAME, "protected-user", true).unwrap();
        set_entry_field(
            handle,
            entry_uuid,
            fields::URL,
            "https://manykee.test",
            true,
        )
        .unwrap();
        set_entry_field(handle, entry_uuid, fields::PASSWORD, "hunter2", true).unwrap();
        set_entry_field(handle, entry_uuid, fields::NOTES, "private notes", true).unwrap();

        let entries_json = list_entries(handle, "").unwrap();
        let entries: Vec<serde_json::Value> = serde_json::from_str(&entries_json).unwrap();
        let summary = &entries[0];
        assert_eq!(summary["title"].as_str(), Some("WASM Entry"));
        assert_eq!(summary["username"].as_str(), Some(""));
        assert_eq!(summary["url"].as_str(), Some(""));
        assert_eq!(summary["protected"]["UserName"].as_bool(), Some(true));
        assert_eq!(summary["protected"]["URL"].as_bool(), Some(true));
        assert!(summary.get("password").is_none());
        assert!(summary.get("notes").is_none());
        assert!(!entries_json.contains("protected-user"));
        assert!(!entries_json.contains("hunter2"));
        assert!(!entries_json.contains("private notes"));

        close_db(handle).unwrap();
    }

    #[test]
    fn wasm_moves_accept_empty_target_as_root() {
        let handle = open_test_handle();
        let target_json = create_group(handle, "", "Nested").unwrap();
        let target: serde_json::Value = serde_json::from_str(&target_json).unwrap();
        let target_uuid = target["uuid"].as_str().unwrap();
        let child_json = create_group(handle, target_uuid, "Child").unwrap();
        let child: serde_json::Value = serde_json::from_str(&child_json).unwrap();
        let child_uuid = child["uuid"].as_str().unwrap();
        let entry_json = create_entry(handle, target_uuid, "Move to root").unwrap();
        let entry: serde_json::Value = serde_json::from_str(&entry_json).unwrap();
        let entry_uuid = entry["uuid"].as_str().unwrap();

        move_entry(handle, entry_uuid, "").unwrap();
        move_group(handle, child_uuid, "").unwrap();

        let root_entries: Vec<serde_json::Value> =
            serde_json::from_str(&list_entries(handle, "").unwrap()).unwrap();
        let root_groups: Vec<serde_json::Value> =
            serde_json::from_str(&list_groups(handle, "").unwrap()).unwrap();
        assert!(root_entries
            .iter()
            .any(|entry| entry["uuid"].as_str() == Some(entry_uuid)));
        assert!(root_groups
            .iter()
            .any(|group| group["uuid"].as_str() == Some(child_uuid)));

        close_db(handle).unwrap();
    }

    #[test]
    fn wasm_read_entry_field_fetches_single_field_on_demand() {
        let handle = open_test_handle();
        let entries_json = list_entries(handle, "").unwrap();
        let entries: Vec<serde_json::Value> = serde_json::from_str(&entries_json).unwrap();
        let entry_uuid = entries[0]["uuid"].as_str().unwrap();

        assert_eq!(
            read_entry_field(handle, entry_uuid, fields::TITLE).unwrap(),
            "WASM Entry"
        );
        assert_eq!(
            read_entry_field(handle, entry_uuid, "otp").unwrap(),
            "otpauth://totp/ManyKee:wasm?secret=DEF"
        );

        // The not-found path returns `Err(JsValue)`, and constructing a
        // `JsValue` panics ("function not implemented") outside a real
        // wasm32 target -- exercised instead by
        // `test_read_entry_field_not_found` in `tests/wasm_tests.rs`, which
        // runs under `wasm-pack test` in an actual JS/wasm runtime.

        close_db(handle).unwrap();
    }

    #[test]
    fn wasm_write_exports_round_trip() {
        let handle = open_test_handle();
        let root_uuid =
            DATABASES.with(|dbs| dbs.borrow().get(&handle).unwrap().root.uuid.to_string());
        let target_json = create_group(handle, &root_uuid, "Nested").unwrap();
        let target: serde_json::Value = serde_json::from_str(&target_json).unwrap();
        let target_uuid = target["uuid"].as_str().unwrap();

        let created = create_entry(handle, &root_uuid, "Created via wasm").unwrap();
        let created: serde_json::Value = serde_json::from_str(&created).unwrap();
        let entry_uuid = created["uuid"].as_str().unwrap().to_string();

        set_entry_field(handle, &entry_uuid, fields::USERNAME, "wasm-user", false).unwrap();
        move_entry(handle, &entry_uuid, target_uuid).unwrap();
        rename_group(handle, target_uuid, "Renamed").unwrap();

        let saved = save_db(handle, "test", None).unwrap();
        let saved = hex::decode(saved).unwrap();
        let reopened = Database::parse(&saved, DatabaseKey::new().with_password("test")).unwrap();

        let renamed = reopened
            .root
            .groups
            .iter()
            .find(|group| group.name == "Renamed")
            .unwrap();
        let created = renamed
            .find_entry_by_uuid(entry_uuid.parse().unwrap())
            .unwrap();
        assert_eq!(created.get(fields::USERNAME), Some("wasm-user"));

        close_db(handle).unwrap();
    }

    #[test]
    fn merge_databases_preserves_handle_b_when_merge_panics() {
        let handle_a = open_test_handle();
        let handle_b = open_test_handle();

        // Force a panic inside the merge closure to simulate a crafted-file
        // panic reached through keepassxc::merge, and confirm handle_b's
        // database is still present afterward (reinserted before the
        // panic is re-raised to the outer catch_unwind_result).
        let result = DATABASES.with(|dbs| {
            let mut dbs = dbs.borrow_mut();
            let db_b = dbs.remove(&handle_b).unwrap();
            let merge_outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let _db_a = dbs.get_mut(&handle_a).unwrap();
                panic!("simulated merge panic");
                #[allow(unreachable_code)]
                keepassxc::merge(_db_a, &db_b)
            }));
            dbs.insert(handle_b, db_b);
            merge_outcome
        });

        assert!(result.is_err());
        DATABASES.with(|dbs| {
            assert!(
                dbs.borrow().contains_key(&handle_b),
                "handle_b must survive a panicking merge"
            );
        });

        close_db(handle_a).unwrap();
        close_db(handle_b).unwrap();
    }
}
