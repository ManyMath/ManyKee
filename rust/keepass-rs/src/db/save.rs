use thiserror::Error;

use crate::{config::DatabaseVersion, db::Database, DatabaseKey};

impl Database {
    pub fn save(
        &self,
        destination: &mut dyn std::io::Write,
        key: DatabaseKey,
    ) -> Result<(), DatabaseSaveError> {
        match self.config.version {
            DatabaseVersion::KDB(_) => Err(DatabaseSaveError::UnsupportedVersion),
            DatabaseVersion::KDB2(_) => Err(DatabaseSaveError::UnsupportedVersion),
            DatabaseVersion::KDB3(_) => save_kdbx3(self, &key, destination),
            DatabaseVersion::KDB4(_) => save_kdbx4(self, &key, destination),
        }
    }

    /// The lowest KDBX version able to represent this database's content
    /// (see [`crate::format::compat::minimum_required_version`]), regardless
    /// of what `self.config.version` is currently set to.
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    pub fn minimum_required_version(&self) -> DatabaseVersion {
        crate::format::compat::minimum_required_version(self)
    }

    /// Save the database at the lowest KDBX version that can represent its
    /// content (see [`crate::format::compat::minimum_required_version`]),
    /// mirroring KeePassXC's compatibility-preserving export. Unlike
    /// [`Database::save`], this never fails with
    /// [`DatabaseSaveError::UnsupportedVersion`]/[`DatabaseSaveError::IncompatibleWithVersion`]
    /// purely due to `self.config.version`, it picks the version itself.
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    pub fn save_compat(
        &self,
        destination: &mut dyn std::io::Write,
        key: DatabaseKey,
    ) -> Result<DatabaseVersion, DatabaseSaveError> {
        let version = crate::format::compat::minimum_required_version(self);

        // `dump_kdbx3`/`dump_kdbx4` write whatever's in `config.version` as
        // the on-disk version header, and `self.config.version` may not
        // already be `version` (e.g. it can downgrade a KDBX4-configured
        // database), so save at a version-adjusted clone rather than
        // mutating `self`.
        if version != self.config.version {
            let mut versioned = self.clone();
            versioned.config.version = version.clone();
            return versioned.save_compat(destination, key);
        }

        match version {
            DatabaseVersion::KDB3(_) => save_kdbx3(self, &key, destination)?,
            DatabaseVersion::KDB4(_) => save_kdbx4(self, &key, destination)?,
            _ => unreachable!("minimum_required_version only returns KDB3/KDB4"),
        };

        Ok(version)
    }
}

#[cfg(feature = "save_kdbx3")]
fn save_kdbx3(
    db: &Database,
    key: &DatabaseKey,
    destination: &mut dyn std::io::Write,
) -> Result<(), DatabaseSaveError> {
    crate::format::kdbx3::dump_kdbx3(db, key, destination)
}

#[cfg(not(feature = "save_kdbx3"))]
fn save_kdbx3(
    _db: &Database,
    _key: &DatabaseKey,
    _destination: &mut dyn std::io::Write,
) -> Result<(), DatabaseSaveError> {
    Err(DatabaseSaveError::UnsupportedVersion)
}

#[cfg(feature = "save_kdbx4")]
fn save_kdbx4(
    db: &Database,
    key: &DatabaseKey,
    destination: &mut dyn std::io::Write,
) -> Result<(), DatabaseSaveError> {
    crate::format::kdbx4::dump_kdbx4(db, key, destination)
}

#[cfg(not(feature = "save_kdbx4"))]
fn save_kdbx4(
    _db: &Database,
    _key: &DatabaseKey,
    _destination: &mut dyn std::io::Write,
) -> Result<(), DatabaseSaveError> {
    Err(DatabaseSaveError::UnsupportedVersion)
}

#[derive(Debug, Error)]
pub enum DatabaseSaveError {
    #[error(transparent)]
    Io(#[from] std::io::Error),

    #[error(transparent)]
    Serialization(#[from] quick_xml::SeError),

    #[error(transparent)]
    Key(#[from] crate::key::DatabaseKeyError),

    #[error(transparent)]
    Cryptography(#[from] crate::crypt::CryptographyError),

    #[error(transparent)]
    Random(#[from] getrandom::Error),

    #[error("Unsupported database version")]
    UnsupportedVersion,

    #[error("Database content is incompatible with the requested KDBX version: {0}")]
    IncompatibleWithVersion(&'static str),
}

#[cfg(all(test, feature = "save_kdbx3", feature = "save_kdbx4"))]
mod save_compat_tests {
    use super::*;
    use crate::{
        config::{DatabaseConfig, InnerCipherConfig, KdfConfig, OuterCipherConfig},
        db::Entry,
        Database,
    };

    #[test]
    fn save_compat_picks_kdbx3_when_content_allows_it() {
        let config = DatabaseConfig {
            version: DatabaseVersion::KDB4(0),
            outer_cipher_config: OuterCipherConfig::AES256,
            compression_config: crate::config::CompressionConfig::GZip,
            inner_cipher_config: InnerCipherConfig::Salsa20,
            kdf_config: KdfConfig::Aes { rounds: 10 },
            public_custom_data: Default::default(),
        };
        let mut db = Database::new(config);
        db.root.entries.push(Entry::new());

        let mut buf = Vec::new();
        let written_version = db
            .save_compat(&mut buf, DatabaseKey::new().with_password("testing"))
            .unwrap();

        assert!(matches!(written_version, DatabaseVersion::KDB3(1)));

        let loaded = Database::open(&mut buf.as_slice(), DatabaseKey::new().with_password("testing")).unwrap();
        assert_eq!(loaded.root.entries.len(), 1);
    }

    #[test]
    fn save_compat_picks_kdbx4_when_content_requires_it() {
        // The default config uses Argon2 + ChaCha20, which KDBX3 can't represent.
        let db = Database::new(DatabaseConfig::default());

        let mut buf = Vec::new();
        let written_version = db
            .save_compat(&mut buf, DatabaseKey::new().with_password("testing"))
            .unwrap();

        assert!(matches!(written_version, DatabaseVersion::KDB4(_)));

        let loaded = Database::open(&mut buf.as_slice(), DatabaseKey::new().with_password("testing")).unwrap();
        assert_eq!(loaded, db);
    }
}
