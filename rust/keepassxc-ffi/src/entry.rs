//! Entry CRUD FFI functions.

use std::ffi::{c_char, c_int, CString};
use std::time::{SystemTime, UNIX_EPOCH};

use keepassxc::{
    delete_entry, move_entry, read_entry_fields, read_entry_totp_at, update_entry, Entry, EntryExt,
    EntryFieldExt, GroupExt,
};
use uuid::Uuid;

use crate::database::KpxcDatabase;
use crate::error::{
    check_null, clear_last_error, cstr_to_str, set_error_from_kpxc, set_last_error,
    KPXC_ERR_INVALID_UTF8, KPXC_ERR_NULL_PTR, KPXC_OK,
};

/// Parse a UUID string, setting last error on failure.
fn parse_uuid(s: &str) -> Result<Uuid, c_int> {
    Uuid::parse_str(s).map_err(|e| {
        set_last_error(&format!("Invalid UUID '{}': {}", s, e));
        KPXC_ERR_INVALID_UTF8
    })
}

fn field_from_payload<'a>(
    payload: &'a keepassxc::EntryReadFields,
    field_name: &str,
) -> Option<&'a str> {
    payload
        .fields
        .get(field_name)
        .or_else(|| payload.custom_data.get(field_name))
        .map(String::as_str)
}

#[no_mangle]
pub extern "C" fn kpxc_entry_get_field(
    db: *mut KpxcDatabase,
    entry_uuid: *const c_char,
    field_name: *const c_char,
) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    let uuid_str = cstr_to_str!(entry_uuid, std::ptr::null_mut());
    let field_str = cstr_to_str!(field_name, std::ptr::null_mut());

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(_) => return std::ptr::null_mut(),
    };

    let db = unsafe { &*db };
    let entry = match db.0.root.find_entry_by_uuid(uuid) {
        Some(e) => e,
        None => {
            set_last_error(&format!("Entry not found: {}", uuid));
            return std::ptr::null_mut();
        }
    };

    let payload = read_entry_fields(entry);
    match field_from_payload(&payload, field_str) {
        Some(value) => match CString::new(value) {
            Ok(cs) => cs.into_raw(),
            Err(_) => {
                set_last_error("Field value contains null byte");
                std::ptr::null_mut()
            }
        },
        None => {
            set_last_error(&format!(
                "Field '{}' not found on entry {}",
                field_str, uuid
            ));
            std::ptr::null_mut()
        }
    }
}

use keepassxc::serialization::{EntryFields, TotpInfo};

#[no_mangle]
pub extern "C" fn kpxc_entry_read_fields(
    db: *mut KpxcDatabase,
    entry_uuid: *const c_char,
) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    let uuid_str = cstr_to_str!(entry_uuid, std::ptr::null_mut());

    let uuid = match parse_uuid(uuid_str) {
        Ok(uuid) => uuid,
        Err(_) => return std::ptr::null_mut(),
    };

    let db = unsafe { &*db };
    let entry = match db.0.root.find_entry_by_uuid(uuid) {
        Some(entry) => entry,
        None => {
            set_last_error(&format!("Entry not found: {}", uuid));
            return std::ptr::null_mut();
        }
    };

    let payload = read_entry_fields(entry);
    let fields = EntryFields::from(payload);

    match serde_json::to_string(&fields) {
        Ok(json) => match CString::new(json) {
            Ok(cs) => cs.into_raw(),
            Err(_) => {
                set_last_error("JSON contains null byte");
                std::ptr::null_mut()
            }
        },
        Err(e) => {
            set_last_error(&format!("Failed to serialize fields: {}", e));
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn kpxc_entry_get_totp(
    db: *mut KpxcDatabase,
    entry_uuid: *const c_char,
) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    let uuid_str = cstr_to_str!(entry_uuid, std::ptr::null_mut());

    let uuid = match parse_uuid(uuid_str) {
        Ok(uuid) => uuid,
        Err(_) => return std::ptr::null_mut(),
    };

    let db = unsafe { &*db };
    let entry = match db.0.root.find_entry_by_uuid(uuid) {
        Some(entry) => entry,
        None => {
            set_last_error(&format!("Entry not found: {}", uuid));
            return std::ptr::null_mut();
        }
    };

    let now = match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_secs(),
        Err(error) => {
            set_last_error(&format!("Failed to determine current time: {}", error));
            return std::ptr::null_mut();
        }
    };

    let payload = match read_entry_totp_at(entry, now) {
        Ok(payload) => payload,
        Err(error) => {
            set_last_error(&format!("Failed to read TOTP payload: {}", error));
            return std::ptr::null_mut();
        }
    };

    let json = match payload {
        Some(payload) => {
            let info = TotpInfo::from(payload);
            serde_json::to_string(&info).unwrap_or_else(|_| "null".to_string())
        }
        None => "null".to_string(),
    };

    match CString::new(json) {
        Ok(value) => value.into_raw(),
        Err(_) => {
            set_last_error("TOTP payload contains null byte");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn kpxc_entry_set_field(
    db: *mut KpxcDatabase,
    entry_uuid: *const c_char,
    field_name: *const c_char,
    value: *const c_char,
    protected: c_int,
) -> c_int {
    clear_last_error();
    check_null!(db, KPXC_ERR_NULL_PTR);
    let uuid_str = cstr_to_str!(entry_uuid, KPXC_ERR_NULL_PTR);
    let field_str = cstr_to_str!(field_name, KPXC_ERR_NULL_PTR);
    let value_str = cstr_to_str!(value, KPXC_ERR_NULL_PTR);

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(code) => return code,
    };

    let db = unsafe { &mut *db };
    let is_protected = protected != 0;

    let field_owned = field_str.to_string();
    let value_owned = value_str.to_string();

    let meta = db.0.meta.clone();
    match update_entry(&mut db.0.root, uuid, &meta, |e| {
        e.set_field(&field_owned, &value_owned, is_protected);
    }) {
        Ok(()) => KPXC_OK,
        Err(e) => set_error_from_kpxc(&e),
    }
}

#[no_mangle]
pub extern "C" fn kpxc_entry_get_uuid(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
    index: usize,
) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    let uuid_str = cstr_to_str!(group_uuid, std::ptr::null_mut());

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(_) => return std::ptr::null_mut(),
    };

    let db = unsafe { &*db };
    let group = match db.0.root.find_group_by_uuid(uuid) {
        Some(g) => g,
        None => {
            set_last_error(&format!("Group not found: {}", uuid));
            return std::ptr::null_mut();
        }
    };

    match group.entries.get(index) {
        Some(entry) => match CString::new(entry.uuid.to_string()) {
            Ok(cs) => cs.into_raw(),
            Err(_) => {
                set_last_error("Failed to create UUID string");
                std::ptr::null_mut()
            }
        },
        None => {
            set_last_error(&format!("Entry index {} out of bounds", index));
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn kpxc_entry_create(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    let uuid_str = cstr_to_str!(group_uuid, std::ptr::null_mut());

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(_) => return std::ptr::null_mut(),
    };

    let db = unsafe { &mut *db };
    let group = match db.0.root.find_group_by_uuid_mut(uuid) {
        Some(g) => g,
        None => {
            set_last_error(&format!("Group not found: {}", uuid));
            return std::ptr::null_mut();
        }
    };

    let entry = Entry::new();
    let new_uuid = entry.uuid;
    group.add_entry(entry);

    match CString::new(new_uuid.to_string()) {
        Ok(cs) => cs.into_raw(),
        Err(_) => {
            set_last_error("Failed to create UUID string");
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn kpxc_entry_delete(
    db: *mut KpxcDatabase,
    entry_uuid: *const c_char,
    permanent: c_int,
) -> c_int {
    clear_last_error();
    check_null!(db, KPXC_ERR_NULL_PTR);
    let uuid_str = cstr_to_str!(entry_uuid, KPXC_ERR_NULL_PTR);

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(code) => return code,
    };

    let db = unsafe { &mut *db };
    let soft = permanent == 0;

    match delete_entry(&mut db.0, uuid, soft) {
        Ok(()) => KPXC_OK,
        Err(e) => set_error_from_kpxc(&e),
    }
}

#[no_mangle]
pub extern "C" fn kpxc_entry_move(
    db: *mut KpxcDatabase,
    entry_uuid: *const c_char,
    target_group_uuid: *const c_char,
) -> c_int {
    clear_last_error();
    check_null!(db, KPXC_ERR_NULL_PTR);
    let entry_uuid = cstr_to_str!(entry_uuid, KPXC_ERR_NULL_PTR);
    let target_group_uuid = cstr_to_str!(target_group_uuid, KPXC_ERR_NULL_PTR);

    let entry_uuid = match parse_uuid(entry_uuid) {
        Ok(uuid) => uuid,
        Err(code) => return code,
    };
    let target_group_uuid = match parse_uuid(target_group_uuid) {
        Ok(uuid) => uuid,
        Err(code) => return code,
    };

    let db = unsafe { &mut *db };
    match move_entry(&mut db.0.root, entry_uuid, target_group_uuid) {
        Ok(()) => KPXC_OK,
        Err(error) => set_error_from_kpxc(&error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use keepassxc::{fields, Database, DatabaseConfig};

    use crate::database::KpxcDatabase;

    fn make_db() -> (Box<KpxcDatabase>, Uuid, Uuid) {
        let mut db = Database::new(DatabaseConfig::default());
        let source_uuid = db.root.uuid;
        let target = keepassxc::Group::new("Target");
        let target_uuid = target.uuid;
        db.root.groups.push(target);

        let mut entry = Entry::new();
        entry.set_unprotected(fields::TITLE, "Native OTP");
        entry.custom_data.insert(
            "otp".to_string(),
            keepassxc::CustomDataItem {
                value: Some(keepassxc::CustomDataValue::String(
                    "otpauth://totp/ManyKee:native?secret=ABC".to_string(),
                )),
                last_modification_time: None,
            },
        );
        db.root.entries.push(entry);
        (Box::new(KpxcDatabase(db)), source_uuid, target_uuid)
    }

    #[test]
    fn entry_read_fields_json_includes_custom_data() {
        let handle = make_db().0;
        let db_ptr = Box::into_raw(handle);
        let entry_uuid = unsafe { &*db_ptr }.0.root.entries[0].uuid;
        let entry_uuid = CString::new(entry_uuid.to_string()).unwrap();

        let result = kpxc_entry_read_fields(db_ptr, entry_uuid.as_ptr());
        let json = unsafe { CString::from_raw(result) }.into_string().unwrap();
        let payload: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(
            payload["custom_data"]["otp"].as_str(),
            Some("otpauth://totp/ManyKee:native?secret=ABC")
        );

        unsafe {
            drop(Box::from_raw(db_ptr));
        }
    }

    #[test]
    fn entry_move_updates_tree() {
        let (handle, _, target_uuid) = make_db();
        let db_ptr = Box::into_raw(handle);
        let entry_uuid = unsafe { &*db_ptr }.0.root.entries[0].uuid;

        let entry_uuid = CString::new(entry_uuid.to_string()).unwrap();
        let target_uuid = CString::new(target_uuid.to_string()).unwrap();
        let result = kpxc_entry_move(db_ptr, entry_uuid.as_ptr(), target_uuid.as_ptr());

        assert_eq!(result, KPXC_OK);
        let db = unsafe { &*db_ptr };
        assert!(db.0.root.entries.is_empty());
        assert_eq!(db.0.root.groups[0].entries.len(), 1);

        unsafe {
            drop(Box::from_raw(db_ptr));
        }
    }
}
