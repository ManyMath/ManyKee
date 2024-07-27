//! YubiKey integration tests for keepassxc crate.
//!
//! Requirements covered:
//! YUBI-01 -- list_yubikeys() returns available YubiKey devices
//! YUBI-02 -- open_with_yubikey() opens a database protected with YubiKey
//! YUBI-03 -- LocalChallenge allows CI-safe testing without physical hardware
//! YUBI-04 -- Database created with YubiKey 2FA can be reopened with the same key

use std::io::Cursor;

use keepass::config::DatabaseConfig;
use keepass::{Database, DatabaseKey};
use keepassxc::{
 list_yubikeys, open_with_local_challenge, open_with_yubikey, ChallengeResponseKey,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Create and save a database with password + LocalChallenge, returning raw bytes.
fn create_db_with_challenge(password: &str, hex_secret: &str) -> Vec<u8> {
 let cr_key = ChallengeResponseKey::LocalChallenge(hex_secret.to_string());
 let key = DatabaseKey::new()
 .with_password(password)
 .with_challenge_response_key(cr_key);
 let db = Database::new(DatabaseConfig::default());
 let mut buf = Vec::new();
 db.save(&mut buf, key).expect("save failed");
 buf
}

// ---------------------------------------------------------------------------
// CI-safe tests (no physical YubiKey required)
// ---------------------------------------------------------------------------

#[test]
fn test_local_challenge_round_trip() {
 let password = "test123";
 let hex_secret = "0123456789abcdef0123456789abcdef01234567";

 let data = create_db_with_challenge(password, hex_secret);

 // Reopen with same credentials
 let cr_key = ChallengeResponseKey::LocalChallenge(hex_secret.to_string());
 let key = DatabaseKey::new()
 .with_password(password)
 .with_challenge_response_key(cr_key);

 let mut cursor = Cursor::new(&data);
 let db = Database::open(&mut cursor, key).expect("round-trip open failed");

 // Root group name should match the default
 assert!(
 !db.root.name.is_empty(),
 "root group name should not be empty after round-trip"
 );
}

#[test]
fn test_local_challenge_wrong_secret_fails() {
 let password = "test123";
 let hex_secret = "0123456789abcdef0123456789abcdef01234567";
 let wrong_secret = "abcdef0123456789abcdef0123456789abcdef01";

 let data = create_db_with_challenge(password, hex_secret);

 // Attempt reopen with wrong secret
 let cr_key = ChallengeResponseKey::LocalChallenge(wrong_secret.to_string());
 let key = DatabaseKey::new()
 .with_password(password)
 .with_challenge_response_key(cr_key);

 let mut cursor = Cursor::new(&data);
 let result = Database::open(&mut cursor, key);

 assert!(
 result.is_err(),
 "opening with wrong challenge secret should fail"
 );
}

#[test]
fn test_open_with_local_challenge_convenience() {
 let password = "test123";
 let hex_secret = "0123456789abcdef0123456789abcdef01234567";

 let data = create_db_with_challenge(password, hex_secret);

 let mut cursor = Cursor::new(&data);
 let db = open_with_local_challenge(&mut cursor, password, hex_secret)
 .expect("open_with_local_challenge convenience should succeed");

 assert!(
 !db.root.name.is_empty(),
 "root group name should not be empty"
 );
}

// ---------------------------------------------------------------------------
// Hardware tests (require physical YubiKey -- run with `cargo test -- --ignored`)
// ---------------------------------------------------------------------------

#[test]
#[ignore]
fn test_list_yubikeys_hardware() {
 let devices = list_yubikeys().expect("list_yubikeys should succeed with YubiKey connected");
 assert!(
 !devices.is_empty(),
 "at least one YubiKey should be detected"
 );
 for device in &devices {
 println!(
 "Found YubiKey: serial={} name={:?}",
 device.serial_number, device.name
 );
 }
}

#[test]
#[ignore]
fn test_open_with_yubikey_hardware() {
 let password = "test-yubikey-hw";

 // Get the first available YubiKey
 let devices = list_yubikeys().expect("list_yubikeys failed");
 assert!(!devices.is_empty(), "no YubiKey connected");
 let serial = devices[0].serial_number;

 // Create a DB with the YubiKey challenge-response on slot 2
 let yubikey = ChallengeResponseKey::get_yubikey(Some(serial))
 .expect("get_yubikey failed");
 let cr_key = ChallengeResponseKey::YubikeyChallenge(yubikey, "2".to_string());
 let key = DatabaseKey::new()
 .with_password(password)
 .with_challenge_response_key(cr_key);

 let db = Database::new(DatabaseConfig::default());
 let mut buf = Vec::new();
 db.save(&mut buf, key).expect("save with YubiKey failed");

 // Reopen using open_with_yubikey convenience function
 let mut cursor = Cursor::new(&buf);
 let reopened = open_with_yubikey(&mut cursor, password, Some(serial), "2")
 .expect("open_with_yubikey round-trip failed");

 assert!(
 !reopened.root.name.is_empty(),
 "root group name should survive YubiKey round-trip"
 );
}
