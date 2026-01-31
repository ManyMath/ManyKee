use crate::{Entry, EntryReadFields, EntryTotp, Group, MergeResult};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Serialize, Deserialize, Debug)]
pub struct GroupInfo {
    pub uuid: String,
    pub name: String,
}

impl From<&Group> for GroupInfo {
    fn from(group: &Group) -> Self {
        Self {
            uuid: group.uuid.to_string(),
            name: group.name.clone(),
        }
    }
}

#[derive(Serialize, Deserialize, Debug)]
pub struct EntryInfo {
    pub uuid: String,
    pub title: String,
    pub username: String,
    pub url: String,
}

impl From<&Entry> for EntryInfo {
    fn from(entry: &Entry) -> Self {
        Self {
            uuid: entry.uuid.to_string(),
            title: entry.get("Title").unwrap_or("").to_string(),
            username: entry.get("UserName").unwrap_or("").to_string(),
            url: entry.get("URL").unwrap_or("").to_string(),
        }
    }
}

#[derive(Serialize, Deserialize, Debug)]
pub struct EntryFields {
    pub fields: BTreeMap<String, String>,
    pub custom_data: BTreeMap<String, String>,
}

impl From<EntryReadFields> for EntryFields {
    fn from(fields: EntryReadFields) -> Self {
        Self {
            fields: fields.fields,
            custom_data: fields.custom_data,
        }
    }
}

#[derive(Serialize, Deserialize, Debug)]
pub struct TotpInfo {
    pub code: String,
    pub valid_for: u64,
    pub period: u64,
}

impl From<EntryTotp> for TotpInfo {
    fn from(totp: EntryTotp) -> Self {
        Self {
            code: totp.code,
            valid_for: totp.valid_for,
            period: totp.period,
        }
    }
}

#[derive(Serialize, Deserialize, Debug)]
pub struct MergeInfo {
    pub entries_added: usize,
    pub entries_updated: usize,
    pub entries_deleted: usize,
    pub entries_relocated: usize,
    pub groups_added: usize,
    pub groups_updated: usize,
    pub groups_deleted: usize,
    pub groups_relocated: usize,
    pub conflicts: usize,
    pub warnings: Vec<String>,
    pub total_changes: usize,
}

impl From<&MergeResult> for MergeInfo {
    fn from(result: &MergeResult) -> Self {
        Self {
            entries_added: result.entries_added,
            entries_updated: result.entries_updated,
            entries_deleted: result.entries_deleted,
            entries_relocated: result.entries_relocated,
            groups_added: result.groups_added,
            groups_updated: result.groups_updated,
            groups_deleted: result.groups_deleted,
            groups_relocated: result.groups_relocated,
            conflicts: result.conflicts.len(),
            warnings: result.warnings.iter().map(|w| format!("{:?}", w)).collect(),
            total_changes: result.total_changes(),
        }
    }
}
