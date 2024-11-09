//! Controlled public API on top of keepass-rs fork with ManyKee extensions.

pub mod entry;
pub mod error;
pub mod group;
pub mod merge;
pub mod recycle_bin;
#[cfg(feature = "yubikey")]
pub mod yubikey;

pub use entry::{update_entry, EntryExt, EntryFieldExt};
pub use group::GroupExt;
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
