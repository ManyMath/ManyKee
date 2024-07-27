//! ManyKee extension crate -- controlled public API on top of keepass-rs fork.
//!
//! Re-exports core keepass-rs types (D-01) and adds ManyKee-specific
//! convenience methods, error types, and CRUD operations.
//!
//! Does NOT expose format parsing internals or crypto primitives (D-03).

pub mod entry;
pub mod error;
pub mod group;
pub mod merge;
pub mod recycle_bin;
pub mod yubikey;

// Re-export CRUD extension traits and operations
pub use entry::{update_entry, EntryExt, EntryFieldExt};
pub use group::GroupExt;
pub use recycle_bin::{delete_entry, delete_group, get_or_create_recycle_bin};

// Re-export core database types for consumers (D-01: thin wrapper)
pub use keepass::db::{
    Attachment, AutoType, AutoTypeAssociation, Color, CustomDataItem, CustomDataValue, Database,
    Entry, Group, History, MemoryProtection, Meta, Times, Value,
};

pub use keepass::db::fields;

// Re-export error types
pub use keepass::db::{DatabaseFormatError, DatabaseOpenError, DatabaseSaveError};

// Re-export key types
pub use keepass::DatabaseKey;

// Re-export config for database creation
pub use keepass::config::DatabaseConfig;

// Re-export merge API
pub use merge::{merge, ConflictResolution, MergeConflict, MergeResult, MergeWarning};

// Re-export YubiKey convenience API
pub use yubikey::{
    list_yubikeys, open_with_local_challenge, open_with_yubikey, ChallengeResponseKey, Yubikey,
};

// Crate-level error
pub use error::KeePassXcError;
