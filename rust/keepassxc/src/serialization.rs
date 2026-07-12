use crate::{fields, Entry, EntryReadFields, EntryTotp, Group, MergeResult};
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

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct EntryInfo {
    pub uuid: String,
    pub title: String,
    pub username: String,
    pub url: String,
    /// Protection status for the three fields allowed in list summaries.
    pub protected: BTreeMap<String, bool>,
}

impl From<&Entry> for EntryInfo {
    fn from(entry: &Entry) -> Self {
        let (title, title_protected) = summary_field(entry, fields::TITLE);
        let (username, username_protected) = summary_field(entry, fields::USERNAME);
        let (url, url_protected) = summary_field(entry, fields::URL);
        Self {
            uuid: entry.uuid.to_string(),
            title,
            username,
            url,
            protected: BTreeMap::from([
                (fields::TITLE.to_string(), title_protected),
                (fields::USERNAME.to_string(), username_protected),
                (fields::URL.to_string(), url_protected),
            ]),
        }
    }
}

fn summary_field(entry: &Entry, field_name: &str) -> (String, bool) {
    let Some(value) = entry.fields.get(field_name) else {
        return (String::new(), false);
    };
    if value.is_protected() {
        (String::new(), true)
    } else {
        (value.get().clone(), false)
    }
}

#[derive(Serialize, Deserialize, Debug)]
pub struct EntryFields {
    pub fields: BTreeMap<String, String>,
    pub custom_data: BTreeMap<String, String>,
    /// Whether each `fields` entry is KDBX-protected, keyed the same as `fields`.
    pub protected: BTreeMap<String, bool>,
    pub tags: Vec<String>,
}

impl From<EntryReadFields> for EntryFields {
    fn from(fields: EntryReadFields) -> Self {
        Self {
            fields: fields.fields,
            custom_data: fields.custom_data,
            protected: fields.protected,
            tags: fields.tags,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::EntryFieldExt;

    #[test]
    fn entry_info_only_serializes_safe_summary_fields() {
        let mut entry = Entry::new();
        entry.set_field(fields::TITLE, "private title", true);
        entry.set_field(fields::USERNAME, "private user", true);
        entry.set_field(fields::URL, "https://public.example", false);
        entry.set_field(fields::PASSWORD, "never summarize me", true);
        entry.set_field(fields::NOTES, "never summarize these notes", false);
        entry.set_field("Custom", "never summarize custom data", false);

        let info = EntryInfo::from(&entry);
        assert_eq!(info.title, "");
        assert_eq!(info.username, "");
        assert_eq!(info.url, "https://public.example");
        assert_eq!(info.protected.get(fields::TITLE), Some(&true));
        assert_eq!(info.protected.get(fields::USERNAME), Some(&true));
        assert_eq!(info.protected.get(fields::URL), Some(&false));

        let json = serde_json::to_value(info).unwrap();
        let object = json.as_object().unwrap();
        assert_eq!(
            object.keys().map(String::as_str).collect::<Vec<_>>(),
            vec!["protected", "title", "url", "username", "uuid"]
        );
        let serialized = json.to_string();
        assert!(!serialized.contains("never summarize"));
        assert!(!serialized.contains("Password"));
        assert!(!serialized.contains("Notes"));
        assert!(!serialized.contains("Custom"));
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
