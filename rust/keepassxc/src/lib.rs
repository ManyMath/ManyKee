//! Controlled public API on top of keepass-rs fork with ManyKee extensions.

pub mod database;
pub mod entry;
pub mod error;
pub mod group;
pub mod merge;
pub mod recycle_bin;
pub mod serialization;
#[cfg(feature = "yubikey")]
pub mod yubikey;

pub use database::{open_bytes, save_atomic, save_bytes};
pub use entry::{
    move_entry, read_entry_fields, read_entry_totp_at, update_entry, EntryExt, EntryFieldExt,
    EntryReadFields, EntryTotp,
};
pub use group::{create_group, move_group, rename_group, GroupExt};
pub use recycle_bin::{delete_entry, delete_group, get_or_create_recycle_bin};

pub use keepass::db::{
    Attachment, AutoType, AutoTypeAssociation, Color, CustomDataItem, CustomDataValue, Database,
    Entry, Group, History, MemoryProtection, Meta, Times, Value,
};

pub use keepass::db::fields;

pub use keepass::db::{DatabaseFormatError, DatabaseOpenError, DatabaseSaveError};

pub use keepass::DatabaseKey;

pub use keepass::config::DatabaseConfig;

pub use merge::{merge, ConflictResolution, MergeConflict, MergeResult, MergeWarning};

#[cfg(feature = "yubikey")]
pub use yubikey::{
    list_yubikeys, open_with_local_challenge, open_with_yubikey, ChallengeResponseKey, Yubikey,
};

pub use error::KeePassXcError;

/// Extract the Yubikey challenge seed (S) from a KDBX4 file header.
pub fn extract_challenge(db_bytes: &[u8]) -> Result<Vec<u8>, KeePassXcError> {
    const VERSION_HEADER_SIZE: usize = 12;
    const HEADER_KDF_PARAMS: u8 = 11;
    const HEADER_END: u8 = 0;

    if db_bytes.len() < VERSION_HEADER_SIZE + 5 {
        return Err(KeePassXcError::Parse(
            "File too short to be a KDBX database".to_string(),
        ));
    }

    let mut pos = VERSION_HEADER_SIZE;
    loop {
        if pos + 5 > db_bytes.len() {
            return Err(KeePassXcError::Parse(
                "Unexpected end of header".to_string(),
            ));
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
            return Err(KeePassXcError::Parse(
                "Header entry extends past file end".to_string(),
            ));
        }

        if entry_type == HEADER_KDF_PARAMS {
            // Parse VariantDictionary to find the seed (key "S")
            let vd_bytes = &db_bytes[pos..pos + entry_len];
            match extract_vd_seed(vd_bytes) {
                Some(seed) => return Ok(seed),
                None => {
                    return Err(KeePassXcError::Parse(
                        "KDF parameters found but seed key 'S' not found".to_string(),
                    ))
                }
            }
        }

        pos += entry_len;
    }

    Err(KeePassXcError::Parse(
        "KDF parameters header entry not found — is this a KDBX4 file?".to_string(),
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
        let key_len =
            u32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]) as usize;
        pos += 4;

        if pos + key_len > data.len() {
            return None;
        }
        let key = &data[pos..pos + key_len];
        pos += key_len;

        if pos + 4 > data.len() {
            return None;
        }
        let val_len =
            u32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]) as usize;
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
