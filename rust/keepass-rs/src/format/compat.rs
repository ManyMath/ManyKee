//! Computes the lowest KDBX version that can represent a database's content,
//! mirroring KeePassXC's `KeePass2Writer::kdbxVersionRequired` (see
//! `src/format/KeePass2Writer.cpp` in the KeePassXC source).
//!
//! Unlike KeePassXC, this does not yet distinguish KDBX 4.0 from KDBX 4.1:
//! any KDBX4.1-only feature (tags, `PreviousParentGroup`, a custom-data item
//! with a last-modification time) is folded into a plain KDBX4 bump. This is
//! a strict subset of KeePassXC's behavior, it never claims a file needs a
//! version it doesn't, it just doesn't yet write literal `4.1`.

use crate::{
    config::{InnerCipherConfig, KdfConfig, OuterCipherConfig},
    db::{CustomDataItem, Database, Entry, Group},
    format::{DatabaseVersion, KDBX4_CURRENT_MINOR_VERSION},
};

/// Minor version written for a downgraded KDBX3 file, i.e. "KDBX 3.1", the
/// only KDBX3 minor version in practical use.
const KDBX3_CURRENT_MINOR_VERSION: u16 = 1;

/// The lowest KDBX version able to represent everything in `db`, following
/// KeePassXC's "compatibility" export logic: start at KDBX3.1, and bump to
/// KDBX4 the moment a KDBX4-only feature is used.
pub fn minimum_required_version(db: &Database) -> DatabaseVersion {
    if !is_kdbx3_compatible(db) {
        return DatabaseVersion::KDB4(KDBX4_CURRENT_MINOR_VERSION);
    }

    DatabaseVersion::KDB3(KDBX3_CURRENT_MINOR_VERSION)
}

fn is_kdbx3_compatible(db: &Database) -> bool {
    if !matches!(db.config.kdf_config, KdfConfig::Aes { .. }) {
        return false;
    }

    if db.config.outer_cipher_config == OuterCipherConfig::ChaCha20 {
        return false;
    }

    if db.config.inner_cipher_config == InnerCipherConfig::ChaCha20 {
        return false;
    }

    if db
        .config
        .public_custom_data
        .as_ref()
        .is_some_and(|d| !d.data.is_empty())
    {
        return false;
    }

    // Meta-level CustomData already existed pre-KDBX4 (used by plugins);
    // only an item's last-modification timestamp is a KDBX4.1-only addition.
    if !meta_custom_data_is_kdbx3_compatible(&db.meta.custom_data) {
        return false;
    }

    group_is_kdbx3_compatible(&db.root)
}

fn group_is_kdbx3_compatible(group: &Group) -> bool {
    // Group/entry-level CustomData (as opposed to Meta-level) is a
    // KDBX4-only addition, regardless of whether items carry a timestamp.
    if !group.custom_data.is_empty() {
        return false;
    }
    if group.tags.is_some() || group.previous_parent_group.is_some() {
        return false;
    }

    group.groups.iter().all(group_is_kdbx3_compatible) && group.entries.iter().all(entry_is_kdbx3_compatible)
}

fn entry_is_kdbx3_compatible(entry: &Entry) -> bool {
    if !entry.custom_data.is_empty() {
        return false;
    }
    if entry.previous_parent_group.is_some() {
        return false;
    }

    entry
        .history
        .iter()
        .flat_map(|h| h.entries.iter())
        .all(|history_entry| history_entry.custom_data.is_empty())
}

fn meta_custom_data_is_kdbx3_compatible(custom_data: &std::collections::HashMap<String, CustomDataItem>) -> bool {
    custom_data.values().all(|item| item.last_modification_time.is_none())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        config::DatabaseConfig,
        db::{CustomDataValue, Database},
    };

    fn kdbx3_compatible_config() -> DatabaseConfig {
        DatabaseConfig {
            version: DatabaseVersion::KDB4(KDBX4_CURRENT_MINOR_VERSION),
            outer_cipher_config: OuterCipherConfig::AES256,
            compression_config: crate::config::CompressionConfig::GZip,
            inner_cipher_config: InnerCipherConfig::Salsa20,
            kdf_config: KdfConfig::Aes { rounds: 10 },
            public_custom_data: Default::default(),
        }
    }

    #[test]
    fn default_config_requires_kdbx4() {
        let db = Database::new(DatabaseConfig::default());
        assert!(matches!(minimum_required_version(&db), DatabaseVersion::KDB4(_)));
    }

    #[test]
    fn all_aes_config_with_no_extras_allows_kdbx3() {
        let db = Database::new(kdbx3_compatible_config());
        assert!(matches!(minimum_required_version(&db), DatabaseVersion::KDB3(1)));
    }

    #[test]
    fn group_tag_forces_kdbx4() {
        let mut db = Database::new(kdbx3_compatible_config());
        db.root.tags = Some("tag1".to_string());
        assert!(matches!(minimum_required_version(&db), DatabaseVersion::KDB4(_)));
    }

    #[test]
    fn group_previous_parent_forces_kdbx4() {
        let mut db = Database::new(kdbx3_compatible_config());
        db.root.previous_parent_group = Some(uuid::Uuid::new_v4());
        assert!(matches!(minimum_required_version(&db), DatabaseVersion::KDB4(_)));
    }

    #[test]
    fn entry_custom_data_forces_kdbx4() {
        let mut db = Database::new(kdbx3_compatible_config());
        let mut entry = crate::db::Entry::new();
        entry.custom_data.insert(
            "plugin_key".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("value".to_string())),
                last_modification_time: None,
            },
        );
        db.root.entries.push(entry);

        assert!(matches!(minimum_required_version(&db), DatabaseVersion::KDB4(_)));
    }

    #[test]
    fn meta_custom_data_without_timestamp_stays_kdbx3() {
        let mut db = Database::new(kdbx3_compatible_config());
        db.meta.custom_data.insert(
            "plugin_key".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("value".to_string())),
                last_modification_time: None,
            },
        );

        assert!(matches!(minimum_required_version(&db), DatabaseVersion::KDB3(1)));
    }

    #[test]
    fn meta_custom_data_with_timestamp_forces_kdbx4() {
        let mut db = Database::new(kdbx3_compatible_config());
        db.meta.custom_data.insert(
            "plugin_key".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("value".to_string())),
                last_modification_time: Some(crate::db::Times::now()),
            },
        );

        assert!(matches!(minimum_required_version(&db), DatabaseVersion::KDB4(_)));
    }

    #[test]
    fn argon2_kdf_forces_kdbx4() {
        let mut config = kdbx3_compatible_config();
        config.kdf_config = KdfConfig::Argon2id {
            iterations: 1,
            memory: 1024,
            parallelism: 1,
            version: argon2::Version::Version13,
        };
        let db = Database::new(config);

        assert!(matches!(minimum_required_version(&db), DatabaseVersion::KDB4(_)));
    }

    #[test]
    fn chacha20_outer_cipher_forces_kdbx4() {
        let mut config = kdbx3_compatible_config();
        config.outer_cipher_config = OuterCipherConfig::ChaCha20;
        let db = Database::new(config);

        assert!(matches!(minimum_required_version(&db), DatabaseVersion::KDB4(_)));
    }
}
