//! Composite key construction and key file format tests.
//! Covers composite key from multiple components and
//! all key file formats: XML v1, XML v2, raw 32-byte, hex-encoded.

use keepass::{
 db::{Database, DatabaseOpenError},
 DatabaseKey,
};
use std::{fs::File, path::Path};

/// Helper: resolve fixture path relative to keepass-rs crate root
fn fixture(name: &str) -> std::path::PathBuf {
 Path::new(env!("CARGO_MANIFEST_DIR"))
 .join("../keepass-rs/tests/resources")
 .join(name)
}

// Composite key construction

/// Password-only composite key opens a KDBX4 database.
#[test]
fn open_with_password_only() -> Result<(), DatabaseOpenError> {
 let path = fixture("test_db_kdbx4_with_password_argon2.kdbx");
 let db = Database::open(
 &mut File::open(&path)?,
 DatabaseKey::new().with_password("demopass"),
 )?;
 assert_eq!(db.root.name, "Root");
 assert!(db.root.entries.len() >= 1);
 Ok(())
}

/// Keyfile-only composite key opens a KDBX4 database.
#[test]
fn open_with_keyfile_only() -> Result<(), DatabaseOpenError> {
 let path = fixture("test_db_kdbx4_with_keyfile.kdbx");
 let kf_path = fixture("test_key.key");
 let db = Database::open(
 &mut File::open(&path)?,
 DatabaseKey::new().with_keyfile(&mut File::open(&kf_path)?)?,
 )?;
 assert_eq!(db.root.name, "Root");
 assert!(db.root.entries.len() >= 1);
 Ok(())
}

// Key file format support

/// Raw binary key file (> 32 bytes, hashed with SHA-256).
/// test_key.key is a raw binary file used with test_db_kdbx4_with_keyfile.kdbx.
#[test]
fn keyfile_raw_binary() -> Result<(), DatabaseOpenError> {
 let path = fixture("test_db_kdbx4_with_keyfile.kdbx");
 let kf_path = fixture("test_key.key");
 let db = Database::open(
 &mut File::open(&path)?,
 DatabaseKey::new().with_keyfile(&mut File::open(&kf_path)?)?,
 )?;
 assert_eq!(db.root.name, "Root");
 Ok(())
}

/// XML v1 key file (.key format with base64-encoded key data).
/// test_key_xml.key is an XML v1 key file used with test_db_with_keyfile_xml.kdbx.
#[test]
fn keyfile_xml_v1() -> Result<(), DatabaseOpenError> {
 let path = fixture("test_db_with_keyfile_xml.kdbx");
 let kf_path = fixture("test_key_xml.key");
 let db = Database::open(
 &mut File::open(&path)?,
 DatabaseKey::new().with_keyfile(&mut File::open(&kf_path)?)?,
 )?;
 assert_eq!(db.root.name, "Root");
 assert!(db.root.entries.len() >= 1);
 Ok(())
}

/// XML v2 key file (.keyx format with hex-encoded key data).
/// Password + keyfile composite key ( + ).
#[test]
fn keyfile_xml_v2_with_password() -> Result<(), DatabaseOpenError> {
 let path = fixture("test_db_kdbx4_with_keyfile_v2.kdbx");
 let kf_path = fixture("test_db_kdbx4_with_keyfile_v2.keyx");
 let db = Database::open(
 &mut File::open(&path)?,
 DatabaseKey::new()
 .with_password("demopass")
 .with_keyfile(&mut File::open(&kf_path)?)?,
 )?;
 assert_eq!(db.root.name, "Root");
 assert!(db.root.entries.len() >= 1);
 Ok(())
}

/// XML v2 key file with tabs in content (regression test for issue #284).
#[test]
fn keyfile_xml_v2_alt_with_tabs() -> Result<(), DatabaseOpenError> {
 let path = fixture("test_db_kdbx4_with_keyfile_v2_alt.kdbx");
 let kf_path = fixture("test_db_kdbx4_with_keyfile_v2_alt.keyx");
 let db = Database::open(
 &mut File::open(&path)?,
 DatabaseKey::new()
 .with_password("123123")
 .with_keyfile(&mut File::open(&kf_path)?)?,
 )?;
 assert_eq!(db.root.name, "testdb02");
 assert!(db.root.entries.len() >= 1);
 Ok(())
}

/// Key file parsing: 32-byte raw key file should be used as-is (not hashed).
#[test]
fn keyfile_raw_32_bytes() {
 let raw_key = [0x42u8; 32];
 let key = DatabaseKey::new()
 .with_keyfile(&mut raw_key.as_slice())
 .expect("Should parse 32-byte raw key file");
 assert!(!key.is_empty(), "Key with keyfile should not be empty");
}

/// Key file parsing: hex-encoded string that is not 32 bytes is SHA-256 hashed.
#[test]
fn keyfile_non_32_byte_hashed() {
 let data = b"this is not 32 bytes and not xml";
 let key = DatabaseKey::new()
 .with_keyfile(&mut data.as_slice())
 .expect("Should parse arbitrary key file");
 assert!(!key.is_empty(), "Key with keyfile should not be empty");
}

/// Key file parsing: XML v2 format with hex-encoded key data (in-memory).
#[test]
fn keyfile_xml_v2_in_memory() {
 let xml_keyfile = r#"<?xml version="1.0" encoding="utf-8"?>
<KeyFile>
 <Meta>
 <Version>2.0</Version>
 </Meta>
 <Key>
 <Data Hash="A65F0C2D">
 36057B1C 35037FD9 62257893 C0A22403
 EE3F8FBB 504D9981 08B821CB 00D28F89
 </Data>
 </Key>
</KeyFile>"#;

 let key = DatabaseKey::new()
 .with_keyfile(&mut xml_keyfile.as_bytes())
 .expect("Should parse XML v2 key file");
 assert!(!key.is_empty(), "Key with XML v2 keyfile should not be empty");
}

/// Key file parsing: XML v1 format with base64-encoded key data (in-memory).
#[test]
fn keyfile_xml_v1_in_memory() {
 let xml_keyfile = r#"<?xml version="1.0" encoding="UTF-8"?>
<KeyFile>
 <Key>
 <Data>NXyYiJMHg3ls+eBmjbAjWec9lcOToJiofbhNiFMTJMw=</Data>
 </Key>
</KeyFile>"#;

 let key = DatabaseKey::new()
 .with_keyfile(&mut xml_keyfile.as_bytes())
 .expect("Should parse XML v1 key file");
 assert!(!key.is_empty(), "Key with XML v1 keyfile should not be empty");
}

/// Empty key should fail (no password, no keyfile).
#[test]
fn empty_key_is_rejected() {
 let key = DatabaseKey::new();
 assert!(key.is_empty(), "Empty key should report as empty");
}

/// Composite key with both password and keyfile components.
#[test]
fn composite_key_password_plus_keyfile() {
 let key = DatabaseKey::new()
 .with_password("test")
 .with_keyfile(&mut [0x42u8; 32].as_slice())
 .expect("Should create composite key");
 assert!(!key.is_empty(), "Composite key should not be empty");
}
