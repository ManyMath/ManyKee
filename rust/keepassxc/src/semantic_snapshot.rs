//! Deterministic semantic snapshots for compatibility evidence.

use crate::{
    fields, Attachment, AutoType, CustomDataItem, CustomDataValue, Database, Entry, Group,
    MemoryProtection, Meta, Times, Value,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;

const STANDARD_FIELDS: [&str; 5] = [
    fields::TITLE,
    fields::USERNAME,
    fields::PASSWORD,
    fields::URL,
    fields::NOTES,
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SemanticSnapshot {
    pub schema_version: u32,
    pub metadata: MetadataSnapshot,
    pub root_group: GroupSnapshot,
    pub groups: Vec<GroupSnapshot>,
    pub entries: Vec<EntrySnapshot>,
    pub deleted_objects: BTreeMap<String, Option<String>>,
    pub unsupported: BTreeMap<String, String>,
    pub not_observed: BTreeMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MetadataSnapshot {
    pub generator: Option<String>,
    pub database_name: Option<String>,
    pub database_name_changed: Option<String>,
    pub database_description: Option<String>,
    pub database_description_changed: Option<String>,
    pub default_username: Option<String>,
    pub default_username_changed: Option<String>,
    pub maintenance_history_days: Option<usize>,
    pub color: Option<String>,
    pub master_key_changed: Option<String>,
    pub master_key_change_rec: Option<isize>,
    pub master_key_change_force: Option<isize>,
    pub memory_protection: MemoryProtectionSnapshot,
    pub recyclebin_enabled: Option<bool>,
    pub recyclebin_uuid: Option<String>,
    pub recyclebin_changed: Option<String>,
    pub entry_templates_group: Option<String>,
    pub entry_templates_group_changed: Option<String>,
    pub last_selected_group: Option<String>,
    pub last_top_visible_group: Option<String>,
    pub history_max_items: Option<isize>,
    pub history_max_size: Option<isize>,
    pub settings_changed: Option<String>,
    pub custom_data: BTreeMap<String, CustomDataSnapshot>,
    pub unknown_xml: Vec<UnknownXmlSnapshot>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MemoryProtectionSnapshot {
    pub protect_title: Option<bool>,
    pub protect_username: Option<bool>,
    pub protect_password: Option<bool>,
    pub protect_url: Option<bool>,
    pub protect_notes: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GroupSnapshot {
    pub uuid: String,
    pub name: String,
    pub path: String,
    pub order: Vec<usize>,
    pub notes: Option<String>,
    pub icon_id: Option<usize>,
    pub custom_icon_uuid: Option<String>,
    pub tags: Option<String>,
    pub times: TimesSnapshot,
    pub custom_data: BTreeMap<String, CustomDataSnapshot>,
    pub unknown_xml: Vec<UnknownXmlSnapshot>,
    pub entries: Vec<GroupEntrySnapshot>,
    pub children: Vec<GroupSnapshot>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GroupEntrySnapshot {
    pub uuid: String,
    pub title: Option<String>,
    pub path: String,
    pub order: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EntrySnapshot {
    pub uuid: String,
    pub title: Option<String>,
    pub path: String,
    pub parent_group_uuid: String,
    pub parent_group_path: String,
    pub order: Vec<usize>,
    pub fields: BTreeMap<String, FieldSnapshot>,
    pub tags: Vec<String>,
    pub times: TimesSnapshot,
    pub custom_data: BTreeMap<String, CustomDataSnapshot>,
    pub attachments: Vec<AttachmentSnapshot>,
    pub autotype: Option<AutoTypeSnapshot>,
    pub custom_icon: Option<CustomIconSnapshot>,
    pub unknown_xml: Vec<UnknownXmlSnapshot>,
    pub history: Vec<HistoryEntrySnapshot>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistoryEntrySnapshot {
    pub uuid: String,
    pub title: Option<String>,
    pub fields: BTreeMap<String, FieldSnapshot>,
    pub tags: Vec<String>,
    pub times: TimesSnapshot,
    pub custom_data: BTreeMap<String, CustomDataSnapshot>,
    pub attachments: Vec<AttachmentSnapshot>,
    pub autotype: Option<AutoTypeSnapshot>,
    pub custom_icon: Option<CustomIconSnapshot>,
    pub unknown_xml: Vec<UnknownXmlSnapshot>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FieldSnapshot {
    pub value: String,
    pub protected: bool,
    pub standard: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachmentSnapshot {
    pub name: String,
    pub protected: bool,
    pub size: usize,
    pub sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AutoTypeSnapshot {
    pub enabled: bool,
    pub default_sequence: Option<String>,
    pub data_transfer_obfuscation: Option<bool>,
    pub associations: Vec<AutoTypeAssociationSnapshot>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AutoTypeAssociationSnapshot {
    pub window: String,
    pub sequence: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CustomIconSnapshot {
    pub uuid: String,
    pub size: usize,
    pub sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CustomDataSnapshot {
    pub kind: String,
    pub value: Option<String>,
    pub protected: bool,
    pub size: Option<usize>,
    pub sha256: Option<String>,
    pub last_modification_time: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UnknownXmlSnapshot {
    pub name: String,
    pub xml: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TimesSnapshot {
    pub creation: Option<String>,
    pub last_modification: Option<String>,
    pub last_access: Option<String>,
    pub expiry: Option<String>,
    pub location_changed: Option<String>,
    pub expires: Option<bool>,
    pub usage_count: Option<usize>,
}

pub fn snapshot_database(db: &Database) -> SemanticSnapshot {
    let mut groups = Vec::new();
    let mut entries = Vec::new();
    let root_path = group_path("", &db.root.name);
    let root_group = snapshot_group(&db.root, &root_path, &[0], &mut groups, &mut entries);

    groups.sort_by(|left, right| {
        left.path
            .cmp(&right.path)
            .then_with(|| left.uuid.cmp(&right.uuid))
    });
    entries.sort_by(|left, right| {
        left.path
            .cmp(&right.path)
            .then_with(|| left.uuid.cmp(&right.uuid))
    });

    SemanticSnapshot {
        schema_version: 1,
        metadata: snapshot_metadata(&db.meta),
        root_group,
        groups,
        entries,
        deleted_objects: db
            .deleted_objects
            .iter()
            .map(|(uuid, deleted_at)| {
                (
                    uuid.to_string(),
                    deleted_at.as_ref().map(ToString::to_string),
                )
            })
            .collect(),
        unsupported: unsupported_statuses(),
        not_observed: not_observed_statuses(),
    }
}

pub fn snapshot_json_pretty(db: &Database) -> serde_json::Result<String> {
    serde_json::to_string_pretty(&snapshot_database(db))
}

fn snapshot_metadata(meta: &Meta) -> MetadataSnapshot {
    MetadataSnapshot {
        generator: meta.generator.clone(),
        database_name: meta.database_name.clone(),
        database_name_changed: option_to_string(&meta.database_name_changed),
        database_description: meta.database_description.clone(),
        database_description_changed: option_to_string(&meta.database_description_changed),
        default_username: meta.default_username.clone(),
        default_username_changed: option_to_string(&meta.default_username_changed),
        maintenance_history_days: meta.maintenance_history_days,
        color: meta.color.as_ref().map(ToString::to_string),
        master_key_changed: option_to_string(&meta.master_key_changed),
        master_key_change_rec: meta.master_key_change_rec,
        master_key_change_force: meta.master_key_change_force,
        memory_protection: snapshot_memory_protection(meta.memory_protection.as_ref()),
        recyclebin_enabled: meta.recyclebin_enabled,
        recyclebin_uuid: option_to_string(&meta.recyclebin_uuid),
        recyclebin_changed: option_to_string(&meta.recyclebin_changed),
        entry_templates_group: option_to_string(&meta.entry_templates_group),
        entry_templates_group_changed: option_to_string(&meta.entry_templates_group_changed),
        last_selected_group: option_to_string(&meta.last_selected_group),
        last_top_visible_group: option_to_string(&meta.last_top_visible_group),
        history_max_items: meta.history_max_items,
        history_max_size: meta.history_max_size,
        settings_changed: option_to_string(&meta.settings_changed),
        custom_data: snapshot_custom_data(&meta.custom_data),
        unknown_xml: unknown_xml_snapshots(&meta.unknown_xml),
    }
}

fn snapshot_memory_protection(
    memory_protection: Option<&MemoryProtection>,
) -> MemoryProtectionSnapshot {
    match memory_protection {
        Some(memory_protection) => MemoryProtectionSnapshot {
            protect_title: Some(memory_protection.protect_title),
            protect_username: Some(memory_protection.protect_username),
            protect_password: Some(memory_protection.protect_password),
            protect_url: Some(memory_protection.protect_url),
            protect_notes: Some(memory_protection.protect_notes),
        },
        None => MemoryProtectionSnapshot::default(),
    }
}

fn snapshot_group(
    group: &Group,
    path: &str,
    order: &[usize],
    groups: &mut Vec<GroupSnapshot>,
    entries: &mut Vec<EntrySnapshot>,
) -> GroupSnapshot {
    let group_entries: Vec<GroupEntrySnapshot> = group
        .entries
        .iter()
        .enumerate()
        .map(|(index, entry)| {
            let entry_path = entry_path(path, entry);
            let mut entry_order = order.to_vec();
            entry_order.push(index);
            entries.push(snapshot_entry(
                entry,
                group,
                path,
                &entry_path,
                &entry_order,
            ));

            GroupEntrySnapshot {
                uuid: entry.uuid.to_string(),
                title: entry.get(fields::TITLE).map(ToString::to_string),
                path: entry_path,
                order: index,
            }
        })
        .collect();

    let children: Vec<GroupSnapshot> = group
        .groups
        .iter()
        .enumerate()
        .map(|(index, child)| {
            let child_path = group_path(path, &child.name);
            let mut child_order = order.to_vec();
            child_order.push(index);
            snapshot_group(child, &child_path, &child_order, groups, entries)
        })
        .collect();

    let snapshot = GroupSnapshot {
        uuid: group.uuid.to_string(),
        name: group.name.clone(),
        path: path.to_string(),
        order: order.to_vec(),
        notes: group.notes.clone(),
        icon_id: group.icon_id,
        custom_icon_uuid: group.custom_icon_uuid.map(|uuid| uuid.to_string()),
        tags: group.tags.clone(),
        times: snapshot_times(&group.times),
        custom_data: snapshot_custom_data(&group.custom_data),
        unknown_xml: unknown_xml_snapshots(&group.unknown_xml),
        entries: group_entries,
        children,
    };

    groups.push(snapshot.clone());
    snapshot
}

fn snapshot_entry(
    entry: &Entry,
    parent_group: &Group,
    parent_group_path: &str,
    path: &str,
    order: &[usize],
) -> EntrySnapshot {
    EntrySnapshot {
        uuid: entry.uuid.to_string(),
        title: entry.get(fields::TITLE).map(ToString::to_string),
        path: path.to_string(),
        parent_group_uuid: parent_group.uuid.to_string(),
        parent_group_path: parent_group_path.to_string(),
        order: order.to_vec(),
        fields: snapshot_fields(&entry.fields),
        tags: sorted_strings(&entry.tags),
        times: snapshot_times(&entry.times),
        custom_data: snapshot_custom_data(&entry.custom_data),
        attachments: snapshot_attachments(&entry.attachments),
        autotype: entry.autotype.as_ref().map(snapshot_autotype),
        custom_icon: entry.custom_icon.as_ref().map(snapshot_custom_icon),
        unknown_xml: unknown_xml_snapshots(&entry.unknown_xml),
        history: entry
            .history
            .as_ref()
            .map(|history| {
                let mut entries: Vec<HistoryEntrySnapshot> = history
                    .get_entries()
                    .iter()
                    .map(snapshot_history_entry)
                    .collect();
                entries.sort_by(|left, right| {
                    left.title
                        .cmp(&right.title)
                        .then_with(|| left.uuid.cmp(&right.uuid))
                });
                entries
            })
            .unwrap_or_default(),
    }
}

fn snapshot_history_entry(entry: &Entry) -> HistoryEntrySnapshot {
    HistoryEntrySnapshot {
        uuid: entry.uuid.to_string(),
        title: entry.get(fields::TITLE).map(ToString::to_string),
        fields: snapshot_fields(&entry.fields),
        tags: sorted_strings(&entry.tags),
        times: snapshot_times(&entry.times),
        custom_data: snapshot_custom_data(&entry.custom_data),
        attachments: snapshot_attachments(&entry.attachments),
        autotype: entry.autotype.as_ref().map(snapshot_autotype),
        custom_icon: entry.custom_icon.as_ref().map(snapshot_custom_icon),
        unknown_xml: unknown_xml_snapshots(&entry.unknown_xml),
    }
}

fn snapshot_fields(
    fields: &std::collections::HashMap<String, Value<String>>,
) -> BTreeMap<String, FieldSnapshot> {
    fields
        .iter()
        .map(|(name, value)| {
            (
                name.clone(),
                FieldSnapshot {
                    value: value.get().clone(),
                    protected: value.is_protected(),
                    standard: STANDARD_FIELDS.contains(&name.as_str()),
                },
            )
        })
        .collect()
}

fn snapshot_attachments(
    attachments: &std::collections::HashMap<String, Attachment>,
) -> Vec<AttachmentSnapshot> {
    let mut snapshots: Vec<AttachmentSnapshot> = attachments
        .iter()
        .map(|(name, attachment)| {
            let bytes = attachment.data.get();
            AttachmentSnapshot {
                name: name.clone(),
                protected: attachment.data.is_protected(),
                size: bytes.len(),
                sha256: hash_bytes(bytes),
            }
        })
        .collect();
    snapshots.sort_by(|left, right| left.name.cmp(&right.name));
    snapshots
}

fn snapshot_autotype(autotype: &AutoType) -> AutoTypeSnapshot {
    AutoTypeSnapshot {
        enabled: autotype.enabled,
        default_sequence: autotype.default_sequence.clone(),
        data_transfer_obfuscation: autotype.data_transfer_obfuscation,
        associations: autotype
            .associations
            .iter()
            .map(|association| AutoTypeAssociationSnapshot {
                window: association.window.clone(),
                sequence: association.sequence.clone(),
            })
            .collect(),
    }
}

fn snapshot_custom_icon((uuid, bytes): &(uuid::Uuid, Vec<u8>)) -> CustomIconSnapshot {
    CustomIconSnapshot {
        uuid: uuid.to_string(),
        size: bytes.len(),
        sha256: hash_bytes(bytes),
    }
}

fn snapshot_custom_data(
    custom_data: &std::collections::HashMap<String, CustomDataItem>,
) -> BTreeMap<String, CustomDataSnapshot> {
    custom_data
        .iter()
        .map(|(key, item)| {
            let snapshot = match &item.value {
                Some(CustomDataValue::String(value)) => CustomDataSnapshot {
                    kind: "string".to_string(),
                    value: Some(value.clone()),
                    protected: false,
                    size: Some(value.len()),
                    sha256: None,
                    last_modification_time: option_to_string(&item.last_modification_time),
                },
                Some(CustomDataValue::Binary(bytes)) => CustomDataSnapshot {
                    kind: "binary".to_string(),
                    value: None,
                    protected: false,
                    size: Some(bytes.len()),
                    sha256: Some(hash_bytes(bytes)),
                    last_modification_time: option_to_string(&item.last_modification_time),
                },
                None => CustomDataSnapshot {
                    kind: "not_observed".to_string(),
                    value: None,
                    protected: false,
                    size: None,
                    sha256: None,
                    last_modification_time: option_to_string(&item.last_modification_time),
                },
            };
            (key.clone(), snapshot)
        })
        .collect()
}

fn snapshot_times(times: &Times) -> TimesSnapshot {
    TimesSnapshot {
        creation: option_to_string(&times.creation),
        last_modification: option_to_string(&times.last_modification),
        last_access: option_to_string(&times.last_access),
        expiry: option_to_string(&times.expiry),
        location_changed: option_to_string(&times.location_changed),
        expires: times.expires,
        usage_count: times.usage_count,
    }
}

fn unknown_xml_snapshots<T>(nodes: &[T]) -> Vec<UnknownXmlSnapshot>
where
    T: Serialize,
{
    let mut snapshots: Vec<UnknownXmlSnapshot> = nodes
        .iter()
        .map(|node| {
            let xml = match serde_json::to_value(node) {
                Ok(serde_json::Value::String(xml)) => xml,
                Ok(value) => value.to_string(),
                Err(err) => format!("serialization_error:{err}"),
            };
            UnknownXmlSnapshot {
                name: xml_element_name(&xml),
                xml,
            }
        })
        .collect();
    snapshots.sort_by(|left, right| {
        left.name
            .cmp(&right.name)
            .then_with(|| left.xml.cmp(&right.xml))
    });
    snapshots
}

fn xml_element_name(xml: &str) -> String {
    let Some(after_open) = xml.trim_start().strip_prefix('<') else {
        return String::new();
    };
    after_open
        .trim_start_matches('/')
        .split(|ch: char| ch == '>' || ch == '/' || ch.is_whitespace())
        .next()
        .unwrap_or_default()
        .to_string()
}

fn group_path(parent_path: &str, name: &str) -> String {
    if parent_path.is_empty() {
        format!("/{name}")
    } else {
        format!("{parent_path}/{name}")
    }
}

fn entry_path(parent_group_path: &str, entry: &Entry) -> String {
    let title = entry
        .get(fields::TITLE)
        .filter(|title| !title.is_empty())
        .unwrap_or("<untitled>");
    format!("{parent_group_path}/{title}")
}

fn sorted_strings(values: &[String]) -> Vec<String> {
    let mut values = values.to_vec();
    values.sort_by(|left, right| left.cmp(right));
    values
}

fn option_to_string<T: ToString>(value: &Option<T>) -> Option<String> {
    value.as_ref().map(ToString::to_string)
}

fn hash_bytes(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

fn unsupported_statuses() -> BTreeMap<String, String> {
    [
        (
            "unknown_xml_outer_attributes",
            "Current keepass-rs XmlNode preserves element name and inner XML, but not outer element attributes.",
        ),
        (
            "unknown_xml_direct_test_construction",
            "The XmlNode type is not publicly nameable by keepassxc integration tests; fixture parsing can still expose stored unknown XML.",
        ),
        (
            "unreferenced_custom_icon_pool",
            "The current decrypted model exposes group/entry custom icon UUIDs and entry custom icon bytes, but not a database-wide unreferenced custom icon pool.",
        ),
    ]
    .into_iter()
    .map(|(key, value)| (key.to_string(), value.to_string()))
    .collect()
}

fn not_observed_statuses() -> BTreeMap<String, String> {
    [(
        "public_custom_data",
        "DatabaseConfig public custom data details are not exposed through the current keepassxc maintainer API.",
    )]
    .into_iter()
    .map(|(key, value)| (key.to_string(), value.to_string()))
    .collect()
}
