//! Controlled public API on top of keepass-rs fork with ManyKee extensions.

pub mod compat_evidence;
pub mod database;
pub mod entry;
pub mod error;
pub mod group;
pub mod merge;
pub mod recycle_bin;
pub mod semantic_snapshot;
pub mod serialization;
#[cfg(feature = "yubikey")]
pub mod yubikey;

pub use database::{open_bytes, save_atomic, save_bytes};
pub use entry::{
    move_entry, read_entry_field, read_entry_fields, read_entry_totp_at, update_entry, EntryExt,
    EntryFieldExt, EntryReadFields, EntryTotp,
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
    list_yubikeys, open_with_local_challenge, open_with_local_challenge_and_keyfile,
    open_with_yubikey, open_with_yubikey_and_keyfile, ChallengeResponseKey, Yubikey,
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
        let entry_start = pos
            .checked_add(5)
            .ok_or_else(|| KeePassXcError::Parse("Header entry length overflow".to_string()))?;
        if entry_start > db_bytes.len() {
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

        pos = entry_start;

        if entry_type == HEADER_END {
            break;
        }

        let entry_end = pos
            .checked_add(entry_len)
            .ok_or_else(|| KeePassXcError::Parse("Header entry length overflow".to_string()))?;
        if entry_end > db_bytes.len() {
            return Err(KeePassXcError::Parse(
                "Header entry extends past file end".to_string(),
            ));
        }

        if entry_type == HEADER_KDF_PARAMS {
            // Parse VariantDictionary to find the seed (key "S")
            let vd_bytes = &db_bytes[pos..entry_end];
            match extract_vd_seed(vd_bytes) {
                Some(seed) => return Ok(seed),
                None => {
                    return Err(KeePassXcError::Parse(
                        "KDF parameters found but seed key 'S' not found".to_string(),
                    ))
                }
            }
        }

        pos = entry_end;
    }

    Err(KeePassXcError::Parse(
        "KDF parameters header entry not found: is this a KDBX4 file?".to_string(),
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
        pos = pos.checked_add(1)?;

        if entry_type == 0x00 {
            return None; // end of dictionary, "S" not found
        }

        let key_start = pos.checked_add(4)?;
        if key_start > data.len() {
            return None;
        }
        let key_len =
            u32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]) as usize;
        pos = key_start;

        let key_end = pos.checked_add(key_len)?;
        if key_end > data.len() {
            return None;
        }
        let key = &data[pos..key_end];
        pos = key_end;

        let val_start = pos.checked_add(4)?;
        if val_start > data.len() {
            return None;
        }
        let val_len =
            u32::from_le_bytes([data[pos], data[pos + 1], data[pos + 2], data[pos + 3]]) as usize;
        pos = val_start;

        let val_end = pos.checked_add(val_len)?;
        if val_end > data.len() {
            return None;
        }
        let value = &data[pos..val_end];
        pos = val_end;

        if key == b"S" {
            return Some(value.to_vec());
        }
    }
}

#[cfg(test)]
mod header_length_tests {
    use super::*;

    /// A header entry whose declared length is near `u32::MAX` must be rejected
    /// (as "extends past file end") rather than overflow `pos + entry_len` or
    /// panic on the resulting slice, the same class of bug already fixed for
    /// `VariantDictionary::parse`, but reachable here through the WASM entry
    /// point where `usize` can be 32 bits wide.
    #[test]
    fn extract_challenge_does_not_panic_on_huge_entry_len() {
        let mut buf = vec![0u8; 12]; // version header
        buf.push(11); // HEADER_KDF_PARAMS
        buf.extend_from_slice(&u32::MAX.to_le_bytes()); // entry_len near u32::MAX
        let res = extract_challenge(&buf);
        assert!(res.is_err());
    }

    #[test]
    fn extract_challenge_does_not_panic_on_truncated_header() {
        let mut buf = vec![0u8; 12];
        buf.push(11);
        // declared entry_len is missing its remaining bytes entirely
        buf.extend_from_slice(&[0xFF]);
        let res = extract_challenge(&buf);
        assert!(res.is_err());
    }

    #[test]
    fn extract_vd_seed_does_not_panic_on_huge_key_len() {
        let mut data = vec![0u8; 2]; // version
        data.push(0x18); // some non-zero entry type
        data.extend_from_slice(&u32::MAX.to_le_bytes()); // key_len near u32::MAX
        assert_eq!(extract_vd_seed(&data), None);
    }

    #[test]
    fn extract_vd_seed_does_not_panic_on_huge_val_len() {
        let mut data = vec![0u8; 2]; // version
        data.push(0x18); // entry type
        data.extend_from_slice(&1u32.to_le_bytes()); // key_len = 1
        data.push(b'S'); // key
        data.extend_from_slice(&u32::MAX.to_le_bytes()); // val_len near u32::MAX
        assert_eq!(extract_vd_seed(&data), None);
    }
}
