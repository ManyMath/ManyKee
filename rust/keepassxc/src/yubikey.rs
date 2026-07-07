//! YubiKey wrapper for opening databases with challenge-response.

use std::io::{Read, Seek};

use keepass::{Database, DatabaseKey};

pub use keepass::error::ChallengeResponseKeyError;
pub use keepass::ChallengeResponseKey;
pub use keepass::Yubikey;

use crate::error::KeePassXcError;

/// List all connected YubiKey devices capable of challenge-response.
pub fn list_yubikeys() -> Result<Vec<Yubikey>, KeePassXcError> {
    Ok(ChallengeResponseKey::get_available_yubikeys()?)
}

pub fn open_with_yubikey(
    source: &mut (impl Read + Seek),
    password: &str,
    yubikey_serial: Option<u32>,
    slot: &str,
) -> Result<Database, KeePassXcError> {
    let yubikey = ChallengeResponseKey::get_yubikey(yubikey_serial)?;
    let cr_key = ChallengeResponseKey::YubikeyChallenge(yubikey, slot.to_string());
    let key = DatabaseKey::new()
        .with_password(password)
        .with_challenge_response_key(cr_key);
    let db = Database::open(source, key)?;
    Ok(db)
}

pub fn open_with_yubikey_and_keyfile(
    source: &mut (impl Read + Seek),
    password: &str,
    keyfile: &mut impl Read,
    yubikey_serial: Option<u32>,
    slot: &str,
) -> Result<Database, KeePassXcError> {
    let yubikey = ChallengeResponseKey::get_yubikey(yubikey_serial)?;
    let cr_key = ChallengeResponseKey::YubikeyChallenge(yubikey, slot.to_string());
    let key = DatabaseKey::new()
        .with_password(password)
        .with_keyfile(keyfile)?
        .with_challenge_response_key(cr_key);
    let db = Database::open(source, key)?;
    Ok(db)
}

pub fn open_with_local_challenge(
    source: &mut (impl Read + Seek),
    password: &str,
    hex_secret: &str,
) -> Result<Database, KeePassXcError> {
    let cr_key = ChallengeResponseKey::LocalChallenge(hex_secret.to_string());
    let key = DatabaseKey::new()
        .with_password(password)
        .with_challenge_response_key(cr_key);
    let db = Database::open(source, key)?;
    Ok(db)
}

pub fn open_with_local_challenge_and_keyfile(
    source: &mut (impl Read + Seek),
    password: &str,
    keyfile: &mut impl Read,
    hex_secret: &str,
) -> Result<Database, KeePassXcError> {
    let cr_key = ChallengeResponseKey::LocalChallenge(hex_secret.to_string());
    let key = DatabaseKey::new()
        .with_password(password)
        .with_keyfile(keyfile)?
        .with_challenge_response_key(cr_key);
    let db = Database::open(source, key)?;
    Ok(db)
}
