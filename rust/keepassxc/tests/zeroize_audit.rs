//! Compile-time audit: key material types implement ZeroizeOnDrop.
//! trust secrecy + zeroize crates; verify at type level only.
//!
//! These tests pass if they compile -- ZeroizeOnDrop is a compile-time
//! guarantee that sensitive data is zeroed when it goes out of scope.

use zeroize::ZeroizeOnDrop;

/// Compile-time assertion that T implements ZeroizeOnDrop.
fn assert_zeroize_on_drop<T: ZeroizeOnDrop>() {}

#[test]
fn database_key_zeroizes_on_drop() {
 // DatabaseKey stores password and keyfile bytes -- both must be zeroed.
 assert_zeroize_on_drop::<keepass::DatabaseKey>();
}

#[test]
fn database_key_is_default_constructible() {
 // Verify the key type can be default-constructed (important for builder pattern)
 let key = keepass::DatabaseKey::new();
 assert!(key.is_empty(), "Default-constructed key should be empty");
}

#[test]
fn database_key_with_password_is_not_empty() {
 let key = keepass::DatabaseKey::new().with_password("test");
 assert!(!key.is_empty(), "Key with password should not be empty");
}
