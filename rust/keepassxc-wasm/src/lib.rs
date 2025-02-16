//! WASM bindings for keepassxc database operations.

use std::cell::RefCell;
use std::collections::HashMap;

use keepass::DatabaseKey;
use keepassxc::{Database, EntryExt, GroupExt};
use serde_json::json;
use wasm_bindgen::prelude::*;

thread_local! {
 static DATABASES: RefCell<HashMap<u32, Database>> = RefCell::new(HashMap::new());
 static NEXT_HANDLE: RefCell<u32> = RefCell::new(1);
}

fn store_database(db: Database) -> u32 {
 let handle = NEXT_HANDLE.with(|h| {
 let mut h = h.borrow_mut();
 let id = *h;
 *h += 1;
 id
 });
 DATABASES.with(|dbs| dbs.borrow_mut().insert(handle, db));
 handle
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

fn find_group<'a>(
 root: &'a keepassxc::Group,
 uuid_str: &str,
) -> Option<&'a keepassxc::Group> {
 if uuid_str.is_empty() {
 return Some(root);
 }
 let target = uuid::Uuid::parse_str(uuid_str).ok()?;
 root.find_group_by_uuid(target)
}

fn find_entry<'a>(
 root: &'a keepassxc::Group,
 uuid_str: &str,
) -> Option<&'a keepassxc::Entry> {
 let target = uuid::Uuid::parse_str(uuid_str).ok()?;
 root.find_entry_by_uuid(target)
}

fn field_to_string(value: &keepassxc::Value<String>) -> String {
 value.get().clone()
}

#[wasm_bindgen]
pub fn version() -> String {
 env!("CARGO_PKG_VERSION").to_string()
}

#[wasm_bindgen]
pub fn open_db(
 db_bytes: &[u8],
 password: &str,
 key_file_bytes: Option<Vec<u8>>,
) -> Result<String, JsValue> {
 let mut key = DatabaseKey::new();

 if !password.is_empty() {
 key = key.with_password(password);
 }

 if let Some(kf_bytes) = key_file_bytes {
 key = key
 .with_keyfile(&mut kf_bytes.as_slice())
 .map_err(|e| err_json("KEY_FILE_ERROR", &format!("Failed to read key file: {}", e)))?;
 }

 let db = Database::parse(db_bytes, key)
 .map_err(|e| err_json("OPEN_ERROR", &format!("{}", e)))?;

 let handle = store_database(db);
 Ok(json!({"handle": handle}).to_string())
}

#[wasm_bindgen]
pub fn open_db_with_key_file(
 db_bytes: &[u8],
 password: &str,
 key_file_bytes: &[u8],
) -> Result<String, JsValue> {
 let mut key = DatabaseKey::new();
 if !password.is_empty() {
 key = key.with_password(password);
 }
 key = key
 .with_keyfile(&mut &key_file_bytes[..])
 .map_err(|e| err_json("KEY_FILE_ERROR", &format!("Failed to read key file: {}", e)))?;

 let db = Database::parse(db_bytes, key)
 .map_err(|e| err_json("OPEN_ERROR", &format!("{}", e)))?;

 let handle = store_database(db);
 Ok(json!({"handle": handle}).to_string())
}

#[wasm_bindgen]
pub fn open_db_with_challenge_response(
 db_bytes: &[u8],
 password: &str,
 challenge_response_hex: &str,
) -> Result<String, JsValue> {
 let cr_bytes = hex::decode(challenge_response_hex)
 .map_err(|e| err_json("PARSE_ERROR", &format!("Invalid hex in challenge_response: {}", e)))?;

 let key = DatabaseKey::new()
 .with_password(password)
 .with_challenge_response_bytes(cr_bytes);

 let db = Database::parse(db_bytes, key)
 .map_err(|e| err_json("OPEN_ERROR", &format!("{}", e)))?;

 let handle = store_database(db);
 Ok(json!({"handle": handle}).to_string())
}

#[wasm_bindgen]
pub fn close_db(handle: u32) -> Result<(), JsValue> {
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
}

#[wasm_bindgen]
pub fn list_groups(handle: u32, group_uuid: &str) -> Result<String, JsValue> {
 let uuid_owned = group_uuid.to_string();
 with_database(handle, |db| {
 let group = find_group(&db.root, &uuid_owned).ok_or_else(|| {
 err_json("NOT_FOUND", &format!("Group not found: {}", uuid_owned))
 })?;

 let groups: Vec<serde_json::Value> = group
 .groups
 .iter()
 .map(|g| {
 json!({
 "uuid": g.uuid.to_string(),
 "name": g.name.clone(),
 })
 })
 .collect();

 Ok(json!(groups).to_string())
 })?
}

#[wasm_bindgen]
pub fn list_entries(handle: u32, group_uuid: &str) -> Result<String, JsValue> {
 let uuid_owned = group_uuid.to_string();
 with_database(handle, |db| {
 let group = find_group(&db.root, &uuid_owned).ok_or_else(|| {
 err_json("NOT_FOUND", &format!("Group not found: {}", uuid_owned))
 })?;

 let entries: Vec<serde_json::Value> = group
 .entries
 .iter()
 .map(|e| {
 json!({
 "uuid": e.uuid.to_string(),
 "title": e.get("Title").unwrap_or(""),
 "username": e.get("UserName").unwrap_or(""),
 "url": e.get("URL").unwrap_or(""),
 })
 })
 .collect();

 Ok(json!(entries).to_string())
 })?
}

#[wasm_bindgen]
pub fn read_entry_fields(handle: u32, entry_uuid: &str) -> Result<String, JsValue> {
 let uuid_owned = entry_uuid.to_string();
 with_database(handle, |db| {
 let entry = find_entry(&db.root, &uuid_owned).ok_or_else(|| {
 err_json("NOT_FOUND", &format!("Entry not found: {}", uuid_owned))
 })?;

 let mut fields = serde_json::Map::new();
 for (key, value) in &entry.fields {
 fields.insert(key.clone(), serde_json::Value::String(field_to_string(value)));
 }

 Ok(serde_json::Value::Object(fields).to_string())
 })?
}

#[wasm_bindgen]
pub fn merge_databases(handle_a: u32, handle_b: u32) -> Result<String, JsValue> {
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

 let db_a = dbs.get_mut(&handle_a).unwrap();

 let merge_result = keepassxc::merge(db_a, &db_b);

 dbs.insert(handle_b, db_b);

 let result = merge_result.map_err(|e| {
 err_json("MERGE_ERROR", &format!("{}", e))
 })?;

 let warnings: Vec<String> = result
 .warnings
 .iter()
 .map(|w| format!("{:?}", w))
 .collect();

 Ok(json!({
 "entries_added": result.entries_added,
 "entries_updated": result.entries_updated,
 "entries_deleted": result.entries_deleted,
 "entries_relocated": result.entries_relocated,
 "groups_added": result.groups_added,
 "groups_updated": result.groups_updated,
 "groups_deleted": result.groups_deleted,
 "groups_relocated": result.groups_relocated,
 "conflicts": result.conflicts.len(),
 "warnings": warnings,
 "total_changes": result.total_changes(),
 })
 .to_string())
 })
}

#[wasm_bindgen]
pub fn extract_challenge(db_bytes: &[u8]) -> Result<String, JsValue> {
 const VERSION_HEADER_SIZE: usize = 12;
 const HEADER_KDF_PARAMS: u8 = 11;
 const HEADER_END: u8 = 0;

 if db_bytes.len() < VERSION_HEADER_SIZE + 5 {
 return Err(err_json("PARSE_ERROR", "File too short to be a KDBX database"));
 }

 let mut pos = VERSION_HEADER_SIZE;
 loop {
 if pos + 5 > db_bytes.len() {
 return Err(err_json("PARSE_ERROR", "Unexpected end of header"));
 }

 let entry_type = db_bytes[pos];
 let entry_len = u32::from_le_bytes([
 db_bytes[pos + 1],
 db_bytes[pos + 2],
 db_bytes[pos + 3],
 db_bytes[pos + 4],
 ]) as usize;

 pos += 5;

 if entry_type == HEADER_END {
 break;
 }

 if pos + entry_len > db_bytes.len() {
 return Err(err_json("PARSE_ERROR", "Header entry extends past file end"));
 }

 if entry_type == HEADER_KDF_PARAMS {
 // Parse VariantDictionary to find the seed (key "S")
 let vd_bytes = &db_bytes[pos..pos + entry_len];
 match extract_vd_seed(vd_bytes) {
 Some(seed) => return Ok(hex::encode(seed)),
 None => {
 return Err(err_json(
 "PARSE_ERROR",
 "KDF parameters found but seed key 'S' not found",
 ))
 }
 }
 }

 pos += entry_len;
 }

 Err(err_json(
 "PARSE_ERROR",
 "KDF parameters header entry not found — is this a KDBX4 file?",
 ))
}

fn extract_vd_seed(data: &[u8]) -> Option<Vec<u8>> {
 if data.len() < 2 {
 return None;
 }

 let mut pos = 2; // skip version

 loop {
 if pos >= data.len() {
 return None;
 }

 let entry_type = data[pos];
 pos += 1;

 if entry_type == 0x00 {
 return None; // end of dictionary, "S" not found
 }

 if pos + 4 > data.len() {
 return None;
 }
 let key_len = u32::from_le_bytes([
 data[pos],
 data[pos + 1],
 data[pos + 2],
 data[pos + 3],
 ]) as usize;
 pos += 4;

 if pos + key_len > data.len() {
 return None;
 }
 let key = &data[pos..pos + key_len];
 pos += key_len;

 if pos + 4 > data.len() {
 return None;
 }
 let val_len = u32::from_le_bytes([
 data[pos],
 data[pos + 1],
 data[pos + 2],
 data[pos + 3],
 ]) as usize;
 pos += 4;

 if pos + val_len > data.len() {
 return None;
 }
 let value = &data[pos..pos + val_len];
 pos += val_len;

 if key == b"S" {
 return Some(value.to_vec());
 }
 }
}
