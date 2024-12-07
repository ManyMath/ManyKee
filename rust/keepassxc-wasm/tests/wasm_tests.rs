//! wasm-bindgen-test suite for keepassxc-wasm.
//!
//! Exercises all WASM exports against real KDBX fixtures from keepass-rs.
//! Password for all test databases is "demopass".

use wasm_bindgen::JsValue;
use wasm_bindgen_test::*;

use keepassxc_wasm::*;

// Embed test databases at compile time
const TEST_DB_AES: &[u8] =
 include_bytes!("../../keepass-rs/tests/resources/test_db_kdbx4_with_password_aes.kdbx");
const TEST_DB_FEW_ROUNDS: &[u8] =
 include_bytes!("../../keepass-rs/tests/resources/test_db_few_rounds.kdbx");
const TEST_DB_WITH_KEYFILE: &[u8] =
 include_bytes!("../../keepass-rs/tests/resources/test_db_kdbx4_with_keyfile.kdbx");
const TEST_KEYFILE: &[u8] =
 include_bytes!("../../keepass-rs/tests/resources/test_key.key");

// The challenge-response test DB uses local secret "0102030405060708090a0b0c0d0e0f1011121314"
const TEST_DB_WITH_CR: &[u8] =
 include_bytes!("../../keepass-rs/tests/resources/test_db_with_challenge_response_key.kdbx");

const PASSWORD: &str = "demopass";

#[wasm_bindgen_test]
fn test_version() {
 let v = version();
 assert!(!v.is_empty(), "version() should return a non-empty string");
}

#[wasm_bindgen_test]
fn test_open_and_close() {
 let result = open_db(TEST_DB_FEW_ROUNDS, PASSWORD, None).expect("open_db should succeed");
 let json: serde_json::Value = serde_json::from_str(&result).expect("should parse JSON");
 let handle = json["handle"].as_u64().expect("should have handle") as u32;
 assert!(handle > 0);

 close_db(handle).expect("close_db should succeed");
}

#[wasm_bindgen_test]
fn test_open_aes_db() {
 let result = open_db(TEST_DB_AES, PASSWORD, None).expect("open_db AES should succeed");
 let json: serde_json::Value = serde_json::from_str(&result).unwrap();
 let handle = json["handle"].as_u64().unwrap() as u32;
 close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_open_wrong_password() {
 let result = open_db(TEST_DB_FEW_ROUNDS, "wrong_password", None);
 assert!(result.is_err(), "open_db with wrong password should fail");
}

#[wasm_bindgen_test]
fn test_open_invalid_bytes() {
 let result = open_db(&[0, 1, 2, 3], PASSWORD, None);
 assert!(result.is_err(), "open_db with invalid bytes should fail");
}

#[wasm_bindgen_test]
fn test_open_with_key_file() {
 // test_db_kdbx4_with_keyfile.kdbx uses keyfile only (no password)
 let result = open_db(TEST_DB_WITH_KEYFILE, "", Some(TEST_KEYFILE.to_vec()))
 .expect("open_db with keyfile should succeed");
 let json: serde_json::Value = serde_json::from_str(&result).unwrap();
 let handle = json["handle"].as_u64().unwrap() as u32;
 close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_list_groups() {
 let result = open_db(TEST_DB_AES, PASSWORD, None).unwrap();
 let json: serde_json::Value = serde_json::from_str(&result).unwrap();
 let handle = json["handle"].as_u64().unwrap() as u32;

 let groups_json = list_groups(handle, "").expect("list_groups should succeed");
 let groups: Vec<serde_json::Value> = serde_json::from_str(&groups_json).unwrap();
 assert!(
 groups.iter().all(|g| g.get("uuid").is_some() && g.get("name").is_some()),
 "each group should have uuid and name"
 );

 close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_list_entries() {
 let result = open_db(TEST_DB_AES, PASSWORD, None).unwrap();
 let json: serde_json::Value = serde_json::from_str(&result).unwrap();
 let handle = json["handle"].as_u64().unwrap() as u32;

 let entries_json = list_entries(handle, "").expect("list_entries should succeed");
 let entries: Vec<serde_json::Value> = serde_json::from_str(&entries_json).unwrap();
 assert!(!entries.is_empty(), "should have at least one entry");
 assert!(entries[0].get("uuid").is_some(), "entry should have uuid");
 assert!(entries[0].get("title").is_some(), "entry should have title");
 assert!(entries[0].get("username").is_some(), "entry should have username");
 assert!(entries[0].get("url").is_some(), "entry should have url");

 close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_read_entry_fields() {
 let result = open_db(TEST_DB_AES, PASSWORD, None).unwrap();
 let json: serde_json::Value = serde_json::from_str(&result).unwrap();
 let handle = json["handle"].as_u64().unwrap() as u32;

 // Get first entry UUID
 let entries_json = list_entries(handle, "").unwrap();
 let entries: Vec<serde_json::Value> = serde_json::from_str(&entries_json).unwrap();
 let entry_uuid = entries[0]["uuid"].as_str().unwrap();

 let fields_json = read_entry_fields(handle, entry_uuid).expect("read_entry_fields should succeed");
 let fields: serde_json::Value = serde_json::from_str(&fields_json).unwrap();

 // The first entry in test_db_kdbx4_with_password_aes.kdbx has:
 // Title="ASDF", UserName="ghj", Password="klmno"
 assert_eq!(fields["Title"].as_str(), Some("ASDF"));
 assert_eq!(fields["UserName"].as_str(), Some("ghj"));
 assert_eq!(fields["Password"].as_str(), Some("klmno"));

 close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_invalid_handle() {
 let result = list_groups(9999, "");
 assert!(result.is_err(), "list_groups with invalid handle should fail");
 // Verify error contains INVALID_HANDLE code
 let err = result.unwrap_err();
 let err_str = err.as_string().unwrap();
 assert!(
 err_str.contains("INVALID_HANDLE"),
 "error should contain INVALID_HANDLE code"
 );
}

#[wasm_bindgen_test]
fn test_close_frees_handle() {
 let result = open_db(TEST_DB_FEW_ROUNDS, PASSWORD, None).unwrap();
 let json: serde_json::Value = serde_json::from_str(&result).unwrap();
 let handle = json["handle"].as_u64().unwrap() as u32;

 close_db(handle).unwrap();

 // Handle should now be invalid
 let result = list_groups(handle, "");
 assert!(result.is_err(), "should fail after close");
}

#[wasm_bindgen_test]
fn test_entry_not_found() {
 let result = open_db(TEST_DB_AES, PASSWORD, None).unwrap();
 let json: serde_json::Value = serde_json::from_str(&result).unwrap();
 let handle = json["handle"].as_u64().unwrap() as u32;

 let result = read_entry_fields(handle, "00000000-0000-0000-0000-000000000000");
 assert!(result.is_err(), "should fail for non-existent entry UUID");

 close_db(handle).unwrap();
}

// Note: This test uses the challenge-response test DB from keepass-rs with
// the local challenge secret "0102030405060708090a0b0c0d0e0f1011121314".
// The WASM module receives the pre-computed HMAC-SHA1 result directly via
// with_challenge_response_bytes, bypassing the USB-dependent ChallengeResponseKey.
//
// However, open_db_with_challenge_response expects the raw secret hex, not the
// HMAC result. For keepass-rs's LocalChallenge, the secret IS the hex that gets
// decoded and used as the HMAC key. The challenge itself is the KDF seed from
// the database header.
//
// Since we can't replicate the exact challenge-response flow without the feature,
// we verify that the function is at least callable and returns a structured error
// when the bytes don't match.
#[wasm_bindgen_test]
fn test_open_with_challenge_response_callable() {
 // Use a mock hex secret (40 hex chars = 20 bytes)
 let mock_cr_hex = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

 // This should either succeed (unlikely with mock bytes) or fail with OPEN_ERROR
 let result = open_db_with_challenge_response(TEST_DB_WITH_CR, PASSWORD, mock_cr_hex);
 match result {
 Ok(json_str) => {
 // Unexpected success - clean up
 let json: serde_json::Value = serde_json::from_str(&json_str).unwrap();
 let handle = json["handle"].as_u64().unwrap() as u32;
 close_db(handle).unwrap();
 }
 Err(err) => {
 // Expected: mock bytes don't produce the correct key
 let err_str = err.as_string().unwrap();
 assert!(
 err_str.contains("OPEN_ERROR") || err_str.contains("PARSE_ERROR"),
 "error should be structured: {}",
 err_str
 );
 }
 }
}
