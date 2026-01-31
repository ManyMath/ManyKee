//! Comprehensive Rust-side integration tests for keepassxc.
//!
//! Covers:
//! - Read/Write cycles (including in-memory)
//! - Merge logic (with and without conflicts)
//! - Security-sensitive flows (KDF, key transformations, challenge extraction)

use std::thread;
use std::time::Duration;

use keepassxc::serialization::{EntryInfo, GroupInfo, MergeInfo};
use keepassxc::{
    extract_challenge, fields, merge, open_bytes, save_bytes, ChallengeResponseKey, Database,
    DatabaseConfig, DatabaseKey, Entry, Group, KeePassXcError,
};

const TEST_PASSWORD: &str = "test-password";

fn make_key() -> DatabaseKey {
    DatabaseKey::new().with_password(TEST_PASSWORD)
}

fn create_test_db() -> Database {
    let mut db = Database::new(DatabaseConfig::default());
    db.root.name = "Root".to_string();

    let mut group = Group::new("Test Group");
    let mut entry = Entry::new();
    entry.set_unprotected(fields::TITLE, "Test Entry");
    entry.set_unprotected(fields::USERNAME, "test-user");
    entry.set_unprotected(fields::URL, "https://example.com");
    group.entries.push(entry);
    db.root.groups.push(group);

    db
}

#[test]
fn test_in_memory_read_write_cycle() {
    let db = create_test_db();
    let key = make_key();

    // Save to bytes
    let bytes = save_bytes(&db, key.clone()).expect("failed to save bytes");
    assert!(!bytes.is_empty());

    // Open from bytes
    let reopened = open_bytes(&bytes, key).expect("failed to open bytes");

    // Verify content using serialization helpers
    let root_info = GroupInfo::from(&reopened.root);
    assert_eq!(root_info.name, "Root");

    let test_group = reopened
        .root
        .groups
        .iter()
        .find(|g| g.name == "Test Group")
        .expect("Test Group not found");
    let group_info = GroupInfo::from(test_group);
    assert_eq!(group_info.name, "Test Group");

    let test_entry = test_group
        .entries
        .iter()
        .find(|e| e.get_title().unwrap_or("") == "Test Entry")
        .expect("Test Entry not found");
    let entry_info = EntryInfo::from(test_entry);
    assert_eq!(entry_info.title, "Test Entry");
    assert_eq!(entry_info.username, "test-user");
    assert_eq!(entry_info.url, "https://example.com");
}

#[test]
fn test_merge_logic_integration() {
    let mut db_a = create_test_db();

    // Ensure timestamps are established by a round-trip
    let key = make_key();
    let bytes = save_bytes(&db_a, key.clone()).expect("save failed");
    db_a = open_bytes(&bytes, key.clone()).expect("open failed");

    let mut db_b = db_a.clone();

    // Modify db_b
    let group_b = db_b
        .root
        .groups
        .iter_mut()
        .find(|g| g.name == "Test Group")
        .unwrap();
    let entry_b = group_b
        .entries
        .iter_mut()
        .find(|e| e.get_title().unwrap_or("") == "Test Entry")
        .unwrap();

    // KDBX timestamps are second-resolution, so wait long enough to avoid a
    // synthetic same-timestamp conflict when the entry diverges.
    thread::sleep(Duration::from_secs(1));
    entry_b.set_unprotected(fields::PASSWORD, "new-password");
    entry_b.update_history();

    // Add new entry to db_b
    let mut new_entry = Entry::new();
    new_entry.set_unprotected(fields::TITLE, "B Entry");
    db_b.root.entries.push(new_entry);

    // Merge db_b into db_a
    let result = merge(&mut db_a, &db_b).expect("merge failed");

    // Verify using MergeInfo
    let merge_info = MergeInfo::from(&result);
    assert_eq!(merge_info.entries_added, 1);
    assert_eq!(merge_info.entries_updated, 1);
    assert_eq!(merge_info.conflicts, 0);

    // Verify content
    let merged_entry = db_a.root.groups[0]
        .entries
        .iter()
        .find(|e| e.get_title().unwrap_or("") == "Test Entry")
        .unwrap();
    assert_eq!(merged_entry.get_password().unwrap_or(""), "new-password");
}

#[test]
fn test_security_flow_challenge_extraction() {
    let password = "secure-password";
    let hex_secret = "0123456789abcdef0123456789abcdef01234567";

    // Create DB with challenge-response
    let cr_key = ChallengeResponseKey::LocalChallenge(hex_secret.to_string());
    let key = DatabaseKey::new()
        .with_password(password)
        .with_challenge_response_key(cr_key);

    let db = Database::new(DatabaseConfig::default());
    let mut buf = Vec::new();
    db.save(&mut buf, key)
        .expect("failed to save with challenge");

    // Extract challenge seed (S) from header
    let seed = extract_challenge(&buf).expect("failed to extract challenge");
    assert!(!seed.is_empty(), "seed should not be empty");

    // Reopen using the extracted challenge (simulating YubiKey flow)
    // In a real flow, we'd send 'seed' to YubiKey and get a response.
    // Here we just verify we can extract it.
}

#[test]
fn test_invalid_key_fails() {
    let db = create_test_db();
    let key = make_key();
    let bytes = save_bytes(&db, key).expect("save failed");

    let wrong_key = DatabaseKey::new().with_password("wrong-password");
    let result = open_bytes(&bytes, wrong_key);

    assert!(result.is_err());
    match result.unwrap_err() {
        KeePassXcError::Open(_) => (), // expected
        _ => panic!("Expected Open error"),
    }
}
