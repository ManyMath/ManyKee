//! Merge wrapper converting keepass-rs MergeLog to structured results.

use keepass::db::merge::{MergeEventType, MergeLog};
use keepass::db::Database;
use uuid::Uuid;

use crate::error::KeePassXcError;

/// Structured merge result with counts and conflict details.
#[derive(Debug, Clone, Default)]
pub struct MergeResult {
    pub entries_added: usize,
    pub entries_updated: usize,
    pub entries_deleted: usize,
    pub entries_relocated: usize,
    pub groups_added: usize,
    pub groups_updated: usize,
    pub groups_deleted: usize,
    pub groups_relocated: usize,
    pub conflicts: Vec<MergeConflict>,
    pub warnings: Vec<MergeWarning>,
}

/// A conflict that was automatically resolved during merge.
#[derive(Debug, Clone)]
pub struct MergeConflict {
    pub node_uuid: Uuid,
    pub resolution: ConflictResolution,
}

/// How a merge conflict was resolved.
#[derive(Debug, Clone, PartialEq)]
pub enum ConflictResolution {
    /// The entry/group with the newer LastModificationTime won.
    NewerWins,
    /// Both sides had the same timestamp; self (destination) won
    SameTimestampSelfWins,
}

/// Advisory warnings produced during merge.
#[derive(Debug, Clone)]
pub enum MergeWarning {
    /// Two entries/groups had identical timestamps; destination version kept.
    SameTimestampTiebreak { node_uuid: Uuid, message: String },
    /// An entry or group was missing a last modification timestamp.
    MissingTimestamp(String),
    /// A generic warning from the upstream merge implementation.
    Other(String),
}

pub fn merge(db: &mut Database, other: &Database) -> Result<MergeResult, KeePassXcError> {
    let log = db.merge(other)?;
    Ok(MergeResult::from_log(&log))
}

impl MergeResult {
    fn from_log(log: &MergeLog) -> Self {
        let mut result = MergeResult::default();

        for event in &log.events {
            match event.event_type {
                MergeEventType::EntryCreated => result.entries_added += 1,
                MergeEventType::EntryUpdated => result.entries_updated += 1,
                MergeEventType::EntryDeleted => result.entries_deleted += 1,
                MergeEventType::EntryLocationUpdated => result.entries_relocated += 1,
                MergeEventType::GroupCreated => result.groups_added += 1,
                MergeEventType::GroupUpdated => result.groups_updated += 1,
                MergeEventType::GroupDeleted => result.groups_deleted += 1,
                MergeEventType::GroupLocationUpdated => result.groups_relocated += 1,
            }
        }

        for warning in &log.warnings {
            if warning.contains("same modification time")
                && warning.contains("Destination version wins")
            {
                // Extract UUID from warning message if possible
                // Format: "Entry {uuid} has same modification time..."
                let uuid = warning
                    .split_whitespace()
                    .nth(1)
                    .and_then(|s| Uuid::parse_str(s).ok())
                    .unwrap_or(Uuid::nil());
                result.conflicts.push(MergeConflict {
                    node_uuid: uuid,
                    resolution: ConflictResolution::SameTimestampSelfWins,
                });
                result.warnings.push(MergeWarning::SameTimestampTiebreak {
                    node_uuid: uuid,
                    message: warning.clone(),
                });
            } else if warning.contains("did not have a last modification timestamp") {
                result
                    .warnings
                    .push(MergeWarning::MissingTimestamp(warning.clone()));
            } else {
                result.warnings.push(MergeWarning::Other(warning.clone()));
            }
        }

        result
    }

    /// Total number of changes made during merge.
    pub fn total_changes(&self) -> usize {
        self.entries_added
            + self.entries_updated
            + self.entries_deleted
            + self.entries_relocated
            + self.groups_added
            + self.groups_updated
            + self.groups_deleted
            + self.groups_relocated
    }
}
