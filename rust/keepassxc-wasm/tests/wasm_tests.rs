//! Browser-executed wasm-bindgen-test suite for keepassxc-wasm.

use keepassxc::{Database, DatabaseKey};
use keepassxc_wasm::*;
use serde_json::{json, Value};
use wasm_bindgen_test::*;

wasm_bindgen_test_configure!(run_in_browser);

// Embed test databases at compile time.
const TEST_DB_AES: &[u8] =
    include_bytes!("../../keepass-rs/tests/resources/test_db_kdbx4_with_password_aes.kdbx");
const TEST_DB_FEW_ROUNDS: &[u8] =
    include_bytes!("../../keepass-rs/tests/resources/test_db_few_rounds.kdbx");
const TEST_DB_WITH_KEYFILE: &[u8] =
    include_bytes!("../../keepass-rs/tests/resources/test_db_kdbx4_with_keyfile.kdbx");
const TEST_KEYFILE: &[u8] = include_bytes!("../../keepass-rs/tests/resources/test_key.key");
const TEST_DB_WITH_CR: &[u8] =
    include_bytes!("../../keepass-rs/tests/resources/test_db_with_challenge_response_key.kdbx");
const TEST_DB_RICHCONTENT: &[u8] =
    include_bytes!("../../keepassxc/tests/resources/test_db_kdbx4_richcontent.kdbx");

// official KeePassXC 2.7.12 fixtures (cross-surface smoke). Canonical password
// is defined in `rust/keepassxc/tests/bidirectional_parity.rs::FIXTURE_PASSWORD`.
const OFFICIAL_DB_PASSWORD_BASIC: &[u8] = include_bytes!(
    "../../../fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-basic.kdbx"
);
const OFFICIAL_DB_RICHCONTENT: &[u8] =
    include_bytes!("../../../fixtures/compat/official/keepassxc/2.7.12/keepassxc-richcontent.kdbx");
const OFFICIAL_FIXTURE_PASSWORD: &str = "manykee-fixture-password";

const PASSWORD: &str = "demopass";
const RICHCONTENT_PASSWORD: &str = "testpass123";
const AES_ROOT_UUID: &str = "778cffa9-0930-4b0b-8135-a52834fd1dba";
const TOTP_URL: &str =
    "otpauth://totp/Example:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example";

fn install_panic_hook() {
    console_error_panic_hook::set_once();
}

fn parse_json(json: &str) -> Value {
    serde_json::from_str(json).expect("valid JSON response")
}

fn js_err_string(err: wasm_bindgen::JsValue) -> String {
    err.as_string().unwrap_or_else(|| format!("{err:?}"))
}

fn open_handle(db_bytes: &[u8], password: &str) -> u32 {
    let result = open_db(db_bytes, password, None);
    assert!(
        result.is_ok(),
        "open_db should succeed: {}",
        js_err_string(result.unwrap_err())
    );
    let json = parse_json(&result.unwrap());
    json["handle"].as_u64().expect("handle present") as u32
}

fn list_groups_json(handle: u32, group_uuid: &str) -> Vec<Value> {
    let result = list_groups(handle, group_uuid);
    assert!(
        result.is_ok(),
        "list_groups should succeed: {}",
        js_err_string(result.unwrap_err())
    );
    serde_json::from_str(&result.unwrap()).expect("groups JSON array")
}

fn list_entries_json(handle: u32, group_uuid: &str) -> Vec<Value> {
    let result = list_entries(handle, group_uuid);
    assert!(
        result.is_ok(),
        "list_entries should succeed: {}",
        js_err_string(result.unwrap_err())
    );
    serde_json::from_str(&result.unwrap()).expect("entries JSON array")
}

fn read_fields_json(handle: u32, entry_uuid: &str) -> Value {
    let result = read_entry_fields(handle, entry_uuid);
    assert!(
        result.is_ok(),
        "read_entry_fields should succeed: {}",
        js_err_string(result.unwrap_err())
    );
    parse_json(&result.unwrap())
}

fn create_group_uuid(handle: u32, parent_uuid: &str, name: &str) -> String {
    let result = create_group(handle, parent_uuid, name);
    assert!(
        result.is_ok(),
        "create_group should succeed: {}",
        js_err_string(result.unwrap_err())
    );
    let json = parse_json(&result.unwrap());
    json["uuid"]
        .as_str()
        .expect("group uuid present")
        .to_string()
}

fn create_entry_uuid(handle: u32, group_uuid: &str, title: &str) -> String {
    let result = create_entry(handle, group_uuid, title);
    assert!(
        result.is_ok(),
        "create_entry should succeed: {}",
        js_err_string(result.unwrap_err())
    );
    let json = parse_json(&result.unwrap());
    assert_eq!(json["title"].as_str(), Some(title));
    json["uuid"]
        .as_str()
        .expect("entry uuid present")
        .to_string()
}

fn find_group_uuid_by_name(handle: u32, group_uuid: &str, name: &str) -> Option<String> {
    for group in list_groups_json(handle, group_uuid) {
        if group["name"].as_str() == Some(name) {
            return group["uuid"].as_str().map(ToString::to_string);
        }
        if let Some(uuid) = group["uuid"].as_str() {
            if let Some(found) = find_group_uuid_by_name(handle, uuid, name) {
                return Some(found);
            }
        }
    }
    None
}

fn find_entry_uuid_by_title(handle: u32, group_uuid: &str, title: &str) -> Option<String> {
    for entry in list_entries_json(handle, group_uuid) {
        if entry["title"].as_str() == Some(title) {
            return entry["uuid"].as_str().map(ToString::to_string);
        }
    }
    for group in list_groups_json(handle, group_uuid) {
        if let Some(uuid) = group["uuid"].as_str() {
            if let Some(found) = find_entry_uuid_by_title(handle, uuid, title) {
                return Some(found);
            }
        }
    }
    None
}

#[wasm_bindgen_test]
fn test_version() {
    install_panic_hook();
    assert!(
        !version().is_empty(),
        "version() should return a non-empty string"
    );
}

#[wasm_bindgen_test]
fn test_open_and_close() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_FEW_ROUNDS, PASSWORD);
    assert!(handle > 0);
    close_db(handle).expect("close_db should succeed");
}

#[wasm_bindgen_test]
fn test_direct_parse_few_rounds() {
    install_panic_hook();
    let db = Database::parse(
        TEST_DB_FEW_ROUNDS,
        DatabaseKey::new().with_password(PASSWORD),
    )
    .expect("direct Database::parse should succeed");
    assert_eq!(db.root.name, "Root");
}

#[wasm_bindgen_test]
fn test_open_aes_db() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_AES, PASSWORD);
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_open_wrong_password() {
    install_panic_hook();
    let result = open_db(TEST_DB_FEW_ROUNDS, "wrong_password", None);
    assert!(result.is_err(), "open_db with wrong password should fail");
}

#[wasm_bindgen_test]
fn test_open_invalid_bytes() {
    install_panic_hook();
    let result = open_db(&[0, 1, 2, 3], PASSWORD, None);
    assert!(result.is_err(), "open_db with invalid bytes should fail");
}

#[wasm_bindgen_test]
fn test_open_with_key_file() {
    install_panic_hook();
    let result = open_db(TEST_DB_WITH_KEYFILE, "", Some(TEST_KEYFILE.to_vec()))
        .expect("open_db with keyfile should succeed");
    let json = parse_json(&result);
    let handle = json["handle"].as_u64().unwrap() as u32;
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_list_groups() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_AES, PASSWORD);
    let groups = list_groups_json(handle, "");
    assert!(
        groups
            .iter()
            .all(|group| group.get("uuid").is_some() && group.get("name").is_some()),
        "each group should have uuid and name"
    );
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_list_entries() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_AES, PASSWORD);
    let entries = list_entries_json(handle, "");
    assert!(!entries.is_empty(), "should have at least one entry");
    assert!(entries[0].get("uuid").is_some(), "entry should have uuid");
    assert!(entries[0].get("title").is_some(), "entry should have title");
    assert!(
        entries[0].get("username").is_some(),
        "entry should have username"
    );
    assert!(entries[0].get("url").is_some(), "entry should have url");
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_read_entry_fields_returns_structured_payload() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_RICHCONTENT, RICHCONTENT_PASSWORD);
    let entry_uuid = find_entry_uuid_by_title(handle, "", "TOTPEntry").expect("TOTP entry exists");
    let payload = read_fields_json(handle, &entry_uuid);

    assert!(
        payload.get("Title").is_none(),
        "payload should be structured"
    );
    assert_eq!(payload["fields"]["Title"].as_str(), Some("TOTPEntry"));
    assert_eq!(payload["fields"]["UserName"].as_str(), Some("totpuser"));
    assert!(payload["custom_data"].get("otp").is_none());
    assert!(payload["custom_data"]["KPXC_BROWSER_ENTRY"]
        .as_str()
        .is_some());
    assert!(!payload.to_string().contains(TOTP_URL));
    let totp: Value = parse_json(&get_totp(handle, &entry_uuid).unwrap());
    assert!(totp["code"].as_str().is_some());
    assert!(!totp.to_string().contains(TOTP_URL));

    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_protected_summaries_and_full_reads_do_not_cross_wasm_boundary() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_AES, PASSWORD);
    let entry_uuid = create_entry_uuid(handle, "", "Public title");
    set_entry_field(handle, &entry_uuid, "UserName", "protected-user", true).unwrap();
    set_entry_field(handle, &entry_uuid, "URL", "https://private.test", true).unwrap();
    set_entry_field(handle, &entry_uuid, "Password", "hunter2", true).unwrap();
    set_entry_field(handle, &entry_uuid, "Notes", "private notes", true).unwrap();

    let entries_json = list_entries(handle, "").unwrap();
    let entries: Vec<Value> = serde_json::from_str(&entries_json).unwrap();
    let summary = entries
        .iter()
        .find(|entry| entry["uuid"].as_str() == Some(entry_uuid.as_str()))
        .unwrap();
    assert_eq!(summary["title"].as_str(), Some("Public title"));
    assert_eq!(summary["username"].as_str(), Some(""));
    assert_eq!(summary["url"].as_str(), Some(""));
    assert_eq!(summary["protected"]["UserName"].as_bool(), Some(true));
    assert_eq!(summary["protected"]["URL"].as_bool(), Some(true));
    assert!(summary.get("password").is_none());
    assert!(summary.get("notes").is_none());
    assert!(!entries_json.contains("protected-user"));
    assert!(!entries_json.contains("hunter2"));
    assert!(!entries_json.contains("private notes"));

    let fields = read_fields_json(handle, &entry_uuid);
    assert_eq!(fields["fields"]["UserName"].as_str(), Some(""));
    assert_eq!(fields["fields"]["URL"].as_str(), Some(""));
    assert_eq!(fields["fields"]["Password"].as_str(), Some(""));
    assert_eq!(fields["fields"]["Notes"].as_str(), Some(""));
    assert_eq!(
        read_entry_field(handle, &entry_uuid, "Password").unwrap(),
        "hunter2"
    );

    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_entry_tags_and_root_move_targets_cross_wasm_boundary() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_RICHCONTENT, RICHCONTENT_PASSWORD);
    let tagged_uuid = find_entry_uuid_by_title(handle, "", "TaggedEntry").expect("tagged entry");
    let tagged_fields = read_fields_json(handle, &tagged_uuid);
    assert_eq!(
        tagged_fields["tags"].as_array().unwrap(),
        &[json!("work,important,2fa")]
    );

    let parent_uuid = create_group_uuid(handle, "", "Move Parent");
    let child_uuid = create_group_uuid(handle, &parent_uuid, "Move Child");
    let entry_uuid = create_entry_uuid(handle, &parent_uuid, "Move Entry");
    move_entry(handle, &entry_uuid, "").unwrap();
    move_group(handle, &child_uuid, "").unwrap();

    assert!(list_entries_json(handle, "")
        .iter()
        .any(|entry| entry["uuid"].as_str() == Some(entry_uuid.as_str())));
    assert!(list_groups_json(handle, "")
        .iter()
        .any(|group| group["uuid"].as_str() == Some(child_uuid.as_str())));

    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_write_surface_round_trips_through_save_db() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_AES, PASSWORD);

    let source_uuid = create_group_uuid(handle, AES_ROOT_UUID, "Wasm Source");
    let target_uuid = create_group_uuid(handle, AES_ROOT_UUID, "Wasm Target");
    let nested_uuid = create_group_uuid(handle, &source_uuid, "Wasm Nested");
    let entry_uuid = create_entry_uuid(handle, &source_uuid, "Wasm Entry");

    set_entry_field(handle, &entry_uuid, "UserName", "writer", false).expect("set username");
    set_entry_field(handle, &entry_uuid, "URL", "https://example.test", false).expect("set url");

    let payload = read_fields_json(handle, &entry_uuid);
    assert_eq!(payload["fields"]["Title"].as_str(), Some("Wasm Entry"));
    assert_eq!(payload["fields"]["UserName"].as_str(), Some("writer"));
    assert_eq!(
        payload["fields"]["URL"].as_str(),
        Some("https://example.test")
    );

    move_entry(handle, &entry_uuid, &target_uuid).expect("move_entry should succeed");
    assert!(list_entries_json(handle, &source_uuid)
        .iter()
        .all(|entry| entry["uuid"].as_str() != Some(entry_uuid.as_str())));
    assert!(list_entries_json(handle, &target_uuid)
        .iter()
        .any(|entry| entry["uuid"].as_str() == Some(entry_uuid.as_str())));

    rename_group(handle, &target_uuid, "Wasm Destination").expect("rename_group should succeed");
    move_group(handle, &source_uuid, &target_uuid).expect("move_group should succeed");
    assert!(list_groups_json(handle, &target_uuid)
        .iter()
        .any(|group| group["uuid"].as_str() == Some(source_uuid.as_str())));
    assert!(list_groups_json(handle, &source_uuid)
        .iter()
        .any(|group| group["uuid"].as_str() == Some(nested_uuid.as_str())));

    delete_entry(handle, &entry_uuid).expect("delete_entry should succeed");
    assert!(list_entries_json(handle, &target_uuid)
        .iter()
        .all(|entry| entry["uuid"].as_str() != Some(entry_uuid.as_str())));

    delete_group(handle, &source_uuid).expect("delete_group should succeed");
    assert!(list_groups_json(handle, &target_uuid)
        .iter()
        .all(|group| group["uuid"].as_str() != Some(source_uuid.as_str())));

    let saved_hex = save_db(handle, PASSWORD, None).expect("save_db should succeed");
    let saved_bytes = hex::decode(saved_hex).expect("save_db must return hex");
    let reopened_handle = open_handle(&saved_bytes, PASSWORD);

    let reopened_destination_uuid =
        find_group_uuid_by_name(reopened_handle, "", "Wasm Destination")
            .expect("renamed target group should survive save/reopen");
    assert!(
        find_group_uuid_by_name(reopened_handle, &reopened_destination_uuid, "Wasm Source")
            .is_none(),
        "deleted group should not reappear under the renamed destination after save/reopen"
    );

    close_db(reopened_handle).unwrap();
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_save_db_preserves_key_file_composite_keys() {
    install_panic_hook();

    let handle = open_db(TEST_DB_WITH_KEYFILE, "", Some(TEST_KEYFILE.to_vec()))
        .map(|json| parse_json(&json)["handle"].as_u64().unwrap() as u32)
        .expect("open_db with key file should succeed");

    let entry_uuid = create_entry_uuid(handle, "", "Keyfile Save Entry");
    set_entry_field(handle, &entry_uuid, "UserName", "keyfile-user", false).expect("set username");

    let saved_hex = save_db(handle, "", Some(TEST_KEYFILE.to_vec()))
        .expect("save_db with key file should succeed");
    let saved_bytes = hex::decode(saved_hex).expect("save_db must return hex");
    let reopened_handle = open_db(&saved_bytes, "", Some(TEST_KEYFILE.to_vec()))
        .map(|json| parse_json(&json)["handle"].as_u64().unwrap() as u32)
        .expect("reopen with key file should succeed");

    let reopened_entry = find_entry_uuid_by_title(reopened_handle, "", "Keyfile Save Entry");
    assert!(
        reopened_entry.is_some(),
        "saved entry should survive reopen"
    );

    close_db(reopened_handle).unwrap();
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_invalid_handle() {
    install_panic_hook();
    let result = list_groups(9999, "");
    assert!(
        result.is_err(),
        "list_groups with invalid handle should fail"
    );
    let err_str = result.unwrap_err().as_string().unwrap();
    assert!(
        err_str.contains("INVALID_HANDLE"),
        "error should contain INVALID_HANDLE code"
    );
}

#[wasm_bindgen_test]
fn test_close_frees_handle() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_FEW_ROUNDS, PASSWORD);
    close_db(handle).unwrap();
    let result = list_groups(handle, "");
    assert!(result.is_err(), "should fail after close");
}

#[wasm_bindgen_test]
fn test_entry_not_found() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_AES, PASSWORD);
    let result = read_entry_fields(handle, "00000000-0000-0000-0000-000000000000");
    assert!(result.is_err(), "should fail for non-existent entry UUID");
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_read_entry_field_fetches_single_value() {
    install_panic_hook();
    let handle = open_handle(TEST_DB_AES, PASSWORD);
    let entries = list_entries_json(handle, "");
    let entry_uuid = entries[0]["uuid"].as_str().unwrap();

    let title = read_entry_field(handle, entry_uuid, "Title");
    assert!(
        title.is_ok(),
        "reading an existing field should succeed: {}",
        js_err_string(title.unwrap_err())
    );

    let missing = read_entry_field(handle, entry_uuid, "NoSuchField");
    assert!(
        missing.is_err(),
        "should fail for a field that doesn't exist"
    );

    close_db(handle).unwrap();
}

//: Cross-surface smoke for the official KeePassXC 2.7.12 fixtures.
// These tests run under `wasm-pack test --chrome --headless rust/keepassxc-wasm`
// (CI exercises this; locally requires a headless Chrome binary on PATH).
#[wasm_bindgen_test]
fn test_official_keepassxc_password_basic_opens() {
    install_panic_hook();
    let handle = open_handle(OFFICIAL_DB_PASSWORD_BASIC, OFFICIAL_FIXTURE_PASSWORD);
    let entries = list_entries_json(handle, "");
    let groups = list_groups_json(handle, "");
    assert!(
        !entries.is_empty() || !groups.is_empty(),
        "official keepassxc-password-basic.kdbx should expose at least one entry or group at root"
    );
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_official_keepassxc_richcontent_opens() {
    install_panic_hook();
    let handle = open_handle(OFFICIAL_DB_RICHCONTENT, OFFICIAL_FIXTURE_PASSWORD);
    let entries = list_entries_json(handle, "");
    let groups = list_groups_json(handle, "");
    assert!(
        !entries.is_empty() || !groups.is_empty(),
        "official keepassxc-richcontent.kdbx should expose at least one entry or group at root"
    );
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_open_with_challenge_response_callable() {
    install_panic_hook();
    let mock_cr_hex = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    match open_db_with_challenge_response(TEST_DB_WITH_CR, PASSWORD, mock_cr_hex) {
        Ok(json_str) => {
            let handle = parse_json(&json_str)["handle"].as_u64().unwrap() as u32;
            close_db(handle).unwrap();
        }
        Err(err) => {
            let err_str = err.as_string().unwrap();
            assert!(
                err_str.contains("OPEN_ERROR") || err_str.contains("PARSE_ERROR"),
                "error should be structured: {}",
                err_str
            );
        }
    }
}

/// A crafted `.kdbx` byte buffer that only satisfies enough of the parser to
/// reach the WASM boundary should surface as a structured `Err`, not trap the
/// whole instance. This exercises the same class of malformed input the
/// `catch_unwind_result` wrapper (and the `checked_add` fix in
/// `extract_challenge`/`extract_vd_seed`) is meant to guard against.
#[wasm_bindgen_test]
fn test_open_db_on_garbage_bytes_does_not_trap_instance() {
    install_panic_hook();

    let garbage = vec![0xFFu8; 64];
    let result = open_db(&garbage, PASSWORD, None);
    assert!(result.is_err(), "garbage bytes must be rejected, not panic");

    // The instance must still be usable afterward -- a prior call that
    // panicked without catch_unwind would have trapped it permanently.
    let handle = open_handle(TEST_DB_AES, PASSWORD);
    close_db(handle).unwrap();
}

#[wasm_bindgen_test]
fn test_extract_challenge_on_crafted_huge_length_does_not_trap_instance() {
    install_panic_hook();

    // version header (12 bytes) + a header entry declaring a length near
    // u32::MAX, which used to wrap `pos + entry_len` to a small value on
    // wasm32's 32-bit usize.
    let mut crafted = vec![0u8; 12];
    crafted.push(11); // HEADER_KDF_PARAMS
    crafted.extend_from_slice(&u32::MAX.to_le_bytes());

    let result = extract_challenge(&crafted);
    assert!(
        result.is_err(),
        "crafted huge length must be rejected, not panic"
    );

    // Confirm the instance survived: a normal call still works.
    let handle = open_handle(TEST_DB_AES, PASSWORD);
    close_db(handle).unwrap();
}
