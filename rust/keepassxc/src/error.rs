use keepass::db::merge::MergeError;
use keepass::error::ChallengeResponseKeyError;
use thiserror::Error;
use uuid::Uuid;

/// Unified error type for the keepassxc crate.
/// Wraps upstream keepass-rs errors and adds ManyKee-specific variants.
#[derive(Debug, Error)]
pub enum KeePassXcError {
    #[error("Failed to open database: {0}")]
    Open(#[from] keepass::db::DatabaseOpenError),

    #[error("Failed to save database: {0}")]
    Save(#[from] keepass::db::DatabaseSaveError),

    #[error("Entry not found: {0}")]
    EntryNotFound(Uuid),

    #[error("Group not found: {0}")]
    GroupNotFound(Uuid),

    #[error("Recycle bin is not enabled")]
    RecycleBinDisabled,

    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Merge error: {0}")]
    Merge(#[from] MergeError),

    #[error("Challenge-response error: {0}")]
    ChallengeResponse(#[from] ChallengeResponseKeyError),
}
