//! Entry CRUD traits and history-aware updates.

use std::collections::BTreeMap;

use keepass::db::{CustomDataValue, Entry, Group, Meta, Times, Value};
use uuid::Uuid;

use crate::error::KeePassXcError;
use crate::group::GroupExt;

/// Extension trait for entry CRUD operations on a Group tree.
pub trait EntryExt {
    /// Find an entry by UUID anywhere in the group tree (recursive).
    fn find_entry_by_uuid(&self, uuid: Uuid) -> Option<&Entry>;
    /// Find an entry by UUID anywhere in the group tree (mutable, recursive).
    fn find_entry_by_uuid_mut(&mut self, uuid: Uuid) -> Option<&mut Entry>;
    /// Add an entry to this group's direct entries.
    fn add_entry(&mut self, entry: Entry);
    /// Remove an entry by UUID from anywhere in the group tree. Returns the removed entry.
    fn remove_entry(&mut self, uuid: Uuid) -> Option<Entry>;
}

/// Extension trait for entry field operations.
pub trait EntryFieldExt {
    /// Set a string field. If protected is true, wraps in Value::Protected.
    fn set_field(&mut self, key: &str, value: &str, protected: bool);
    /// Get a string field value.
    fn get_field(&self, key: &str) -> Option<&str>;
}

/// Dart-visible entry field payload used by FFI and WASM reads.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntryReadFields {
    /// Standard KeePass entry fields such as Title, UserName, Password, URL, Notes.
    pub fields: BTreeMap<String, String>,
    /// Entry custom data flattened to strings so keys like `otp` are visible to Dart.
    pub custom_data: BTreeMap<String, String>,
    /// Whether each entry in `fields` is a KDBX-protected value (e.g. Password, or a
    /// custom field marked `Protected="True"`), keyed the same as `fields`.
    pub protected: BTreeMap<String, bool>,
}

/// Dart-visible live TOTP payload used by FFI and WASM reads.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EntryTotp {
    /// The current one-time code.
    pub code: String,
    /// Seconds remaining before the code rotates.
    pub valid_for: u64,
    /// The full TOTP period in seconds.
    pub period: u64,
}

/// Read an entry into a concrete field payload for FFI and WASM.
pub fn read_entry_fields(entry: &Entry) -> EntryReadFields {
    let mut fields = BTreeMap::new();
    let mut protected = BTreeMap::new();
    for (key, value) in &entry.fields {
        fields.insert(key.clone(), value.get().clone());
        protected.insert(key.clone(), value.is_protected());
    }

    let mut custom_data = BTreeMap::new();
    for (key, item) in &entry.custom_data {
        let Some(value) = item.value.as_ref() else {
            continue;
        };
        let value = match value {
            CustomDataValue::String(value) => value.clone(),
            CustomDataValue::Binary(bytes) => encode_hex(bytes),
        };
        custom_data.insert(key.clone(), value);
    }

    EntryReadFields {
        fields,
        custom_data,
        protected,
    }
}

/// Read the live TOTP payload for an entry at a fixed unix timestamp.
pub fn read_entry_totp_at(entry: &Entry, now: u64) -> Result<Option<EntryTotp>, String> {
    let Some(raw_otp) = entry
        .custom_data
        .get("otp")
        .and_then(|item| item.value.as_ref())
        .and_then(|value| match value {
            CustomDataValue::String(value) => Some(value.as_str()),
            CustomDataValue::Binary(_) => None,
        })
    else {
        return Ok(None);
    };

    let totp = raw_otp
        .parse::<keepass::db::TOTP>()
        .map_err(|error| error.to_string())?;
    let code = totp.value_at(now);
    Ok(Some(EntryTotp {
        code: code.code,
        valid_for: code.valid_for.as_secs(),
        period: code.period.as_secs(),
    }))
}

/// Move an entry between groups with an O(n) tree traversal.
///
/// Preserves the entry UUID, last modification timestamp, and history. Move
/// bookkeeping is recorded via `previous_parent_group` and `location_changed`.
pub fn move_entry(
    root: &mut Group,
    entry_uuid: Uuid,
    target_group_uuid: Uuid,
) -> Result<(), KeePassXcError> {
    let source_group_uuid = find_entry_parent_uuid(root, entry_uuid)
        .ok_or(KeePassXcError::EntryNotFound(entry_uuid))?;
    if root.find_group_by_uuid(target_group_uuid).is_none() {
        return Err(KeePassXcError::GroupNotFound(target_group_uuid));
    }
    if source_group_uuid == target_group_uuid {
        return Ok(());
    }

    let (mut entry, _) =
        take_entry(root, entry_uuid).ok_or(KeePassXcError::EntryNotFound(entry_uuid))?;
    entry.previous_parent_group = Some(source_group_uuid);
    entry.times.location_changed = Some(Times::now());

    let target_group = root
        .find_group_by_uuid_mut(target_group_uuid)
        .ok_or(KeePassXcError::GroupNotFound(target_group_uuid))?;
    target_group.add_entry(entry);
    Ok(())
}

/// Update an entry by UUID, snapshotting the old version into history.
/// Enforces history_max_items and history_max_size from Meta.
/// The updater closure receives a mutable reference to the entry.
/// Returns Err(KeePassXcError::EntryNotFound) if UUID not found.
pub fn update_entry<F>(
    root: &mut Group,
    uuid: Uuid,
    meta: &Meta,
    updater: F,
) -> Result<(), KeePassXcError>
where
    F: FnOnce(&mut Entry),
{
    let entry = root
        .find_entry_by_uuid_mut(uuid)
        .ok_or(KeePassXcError::EntryNotFound(uuid))?;

    entry.update_history_with_limits(meta.history_max_items, meta.history_max_size);

    updater(entry);

    entry.times.last_modification = Some(Times::now());

    Ok(())
}

fn encode_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn find_entry_parent_uuid(group: &Group, entry_uuid: Uuid) -> Option<Uuid> {
    if group.entries.iter().any(|entry| entry.uuid == entry_uuid) {
        return Some(group.uuid);
    }
    for child in &group.groups {
        if let Some(parent_uuid) = find_entry_parent_uuid(child, entry_uuid) {
            return Some(parent_uuid);
        }
    }
    None
}

fn take_entry(group: &mut Group, entry_uuid: Uuid) -> Option<(Entry, Uuid)> {
    if let Some(position) = group
        .entries
        .iter()
        .position(|entry| entry.uuid == entry_uuid)
    {
        return Some((group.entries.remove(position), group.uuid));
    }
    for child in &mut group.groups {
        if let Some(found) = take_entry(child, entry_uuid) {
            return Some(found);
        }
    }
    None
}

impl EntryExt for Group {
    fn find_entry_by_uuid(&self, uuid: Uuid) -> Option<&Entry> {
        self.entry_by_uuid(uuid)
    }

    fn find_entry_by_uuid_mut(&mut self, uuid: Uuid) -> Option<&mut Entry> {
        self.entry_by_uuid_mut(uuid)
    }

    fn add_entry(&mut self, entry: Entry) {
        self.entries.push(entry);
    }

    fn remove_entry(&mut self, uuid: Uuid) -> Option<Entry> {
        // Check direct entries
        if let Some(pos) = self.entries.iter().position(|e| e.uuid == uuid) {
            return Some(self.entries.remove(pos));
        }
        // Recurse into child groups
        for group in &mut self.groups {
            if let Some(entry) = group.remove_entry(uuid) {
                return Some(entry);
            }
        }
        None
    }
}

impl EntryFieldExt for Entry {
    fn set_field(&mut self, key: &str, value: &str, protected: bool) {
        if protected {
            self.fields
                .insert(key.to_string(), Value::protected(value.to_string()));
        } else {
            self.fields
                .insert(key.to_string(), Value::unprotected(value.to_string()));
        }
    }

    fn get_field(&self, key: &str) -> Option<&str> {
        self.get(key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use keepass::db::{fields, CustomDataItem, Entry, Group, Meta};

    fn make_entry(title: &str) -> Entry {
        let mut e = Entry::new();
        e.set_unprotected(fields::TITLE, title);
        e
    }

    fn make_group_tree() -> (Group, Uuid, Uuid, Uuid) {
        // root -> child_group -> nested entry
        // -> direct entry
        let mut root = Group::new("Root");
        let mut child = Group::new("Child");

        let direct_entry = make_entry("Direct");
        let nested_entry = make_entry("Nested");
        let direct_uuid = direct_entry.uuid;
        let nested_uuid = nested_entry.uuid;
        let child_uuid = child.uuid;

        child.entries.push(nested_entry);
        root.entries.push(direct_entry);
        root.groups.push(child);

        (root, direct_uuid, nested_uuid, child_uuid)
    }

    #[test]
    fn find_entry_direct() {
        let (root, direct_uuid, _, _) = make_group_tree();
        let found = root.find_entry_by_uuid(direct_uuid);
        assert!(found.is_some());
        assert_eq!(found.unwrap().uuid, direct_uuid);
    }

    #[test]
    fn find_entry_nested() {
        let (root, _, nested_uuid, _) = make_group_tree();
        let found = root.find_entry_by_uuid(nested_uuid);
        assert!(found.is_some());
        assert_eq!(found.unwrap().uuid, nested_uuid);
    }

    #[test]
    fn find_entry_not_found() {
        let (root, _, _, _) = make_group_tree();
        assert!(root.find_entry_by_uuid(Uuid::new_v4()).is_none());
    }

    #[test]
    fn find_entry_mut_works() {
        let (mut root, direct_uuid, _, _) = make_group_tree();
        let found = root.find_entry_by_uuid_mut(direct_uuid);
        assert!(found.is_some());
        assert_eq!(found.unwrap().uuid, direct_uuid);
    }

    #[test]
    fn add_entry_to_group() {
        let mut group = Group::new("Test");
        let entry = make_entry("Added");
        let uuid = entry.uuid;
        group.add_entry(entry);
        assert_eq!(group.entries.len(), 1);
        assert_eq!(group.entries[0].uuid, uuid);
    }

    #[test]
    fn remove_entry_direct() {
        let (mut root, direct_uuid, _, _) = make_group_tree();
        let removed = root.remove_entry(direct_uuid);
        assert!(removed.is_some());
        assert_eq!(removed.unwrap().uuid, direct_uuid);
        assert!(root.find_entry_by_uuid(direct_uuid).is_none());
    }

    #[test]
    fn remove_entry_nested() {
        let (mut root, _, nested_uuid, _) = make_group_tree();
        let removed = root.remove_entry(nested_uuid);
        assert!(removed.is_some());
        assert_eq!(removed.unwrap().uuid, nested_uuid);
        assert!(root.find_entry_by_uuid(nested_uuid).is_none());
    }

    #[test]
    fn remove_entry_not_found() {
        let (mut root, _, _, _) = make_group_tree();
        assert!(root.remove_entry(Uuid::new_v4()).is_none());
    }

    #[test]
    fn set_and_get_field_unprotected() {
        let mut entry = Entry::new();
        entry.set_field("Title", "MyTitle", false);
        assert_eq!(entry.get_field("Title"), Some("MyTitle"));
        assert!(!entry.fields.get("Title").unwrap().is_protected());
    }

    #[test]
    fn set_and_get_field_protected() {
        let mut entry = Entry::new();
        entry.set_field("Password", "secret", true);
        assert_eq!(entry.get_field("Password"), Some("secret"));
        assert!(entry.fields.get("Password").unwrap().is_protected());
    }

    #[test]
    fn get_field_missing() {
        let entry = Entry::new();
        assert!(entry.get_field("NonExistent").is_none());
    }

    #[test]
    fn update_entry_snapshots_history() {
        let (mut root, direct_uuid, _, _) = make_group_tree();
        let meta = Meta::default();

        let result = update_entry(&mut root, direct_uuid, &meta, |e| {
            e.set_unprotected(fields::USERNAME, "new_user");
        });
        assert!(result.is_ok());

        let entry = root.find_entry_by_uuid(direct_uuid).unwrap();
        assert_eq!(entry.get(fields::USERNAME), Some("new_user"));
        assert!(entry.history.is_some());
        assert_eq!(entry.history.as_ref().unwrap().get_entries().len(), 1);
        // The snapshot should NOT have the new username
        let snapshot = &entry.history.as_ref().unwrap().get_entries()[0];
        assert!(snapshot.get(fields::USERNAME).is_none());
    }

    #[test]
    fn update_entry_not_found_returns_error() {
        let (mut root, _, _, _) = make_group_tree();
        let meta = Meta::default();
        let result = update_entry(&mut root, Uuid::new_v4(), &meta, |_| {});
        assert!(result.is_err());
    }

    #[test]
    fn update_entry_enforces_max_items() {
        let mut root = Group::new("Root");
        let entry = make_entry("Test");
        let uuid = entry.uuid;
        root.entries.push(entry);

        let mut meta = Meta::default();
        meta.history_max_items = Some(2);

        // Make 3 updates -- history should be capped at 2
        for i in 0..3 {
            update_entry(&mut root, uuid, &meta, |e| {
                e.set_unprotected(fields::TITLE, &format!("Title {}", i));
            })
            .unwrap();
        }

        let entry = root.find_entry_by_uuid(uuid).unwrap();
        assert_eq!(entry.history.as_ref().unwrap().get_entries().len(), 2);
    }

    #[test]
    fn update_entry_history_max_items_zero_disables_history() {
        let mut root = Group::new("Root");
        let entry = make_entry("Test");
        let uuid = entry.uuid;
        root.entries.push(entry);

        let mut meta = Meta::default();
        meta.history_max_items = Some(0);

        for i in 0..3 {
            update_entry(&mut root, uuid, &meta, |e| {
                e.set_unprotected(fields::TITLE, &format!("Title {}", i));
            })
            .unwrap();
        }

        let entry = root.find_entry_by_uuid(uuid).unwrap();
        assert!(entry.history.as_ref().unwrap().get_entries().is_empty());
    }

    #[test]
    fn update_entry_history_max_size_zero_bounds_history_to_newest_entry() {
        // `History::trim` always keeps at least the newest snapshot even
        // when max_size == 0 (a size limit can't sensibly discard
        // everything), so unlike `history_max_items == Some(0)` this
        // doesn't fully disable history -- but it must still bound growth
        // to a single entry instead of accumulating unboundedly, which is
        // what the old hand-rolled trimming logic did (it skipped size
        // trimming entirely whenever max_bytes == 0).
        let mut root = Group::new("Root");
        let entry = make_entry("Test");
        let uuid = entry.uuid;
        root.entries.push(entry);

        let mut meta = Meta::default();
        meta.history_max_size = Some(0);

        for i in 0..3 {
            update_entry(&mut root, uuid, &meta, |e| {
                e.set_unprotected(fields::TITLE, &format!("Title {}", i));
            })
            .unwrap();
        }

        let entry = root.find_entry_by_uuid(uuid).unwrap();
        assert_eq!(entry.history.as_ref().unwrap().get_entries().len(), 1);
    }

    #[test]
    fn update_entry_preserves_uuid() {
        let (mut root, direct_uuid, _, _) = make_group_tree();
        let meta = Meta::default();

        update_entry(&mut root, direct_uuid, &meta, |e| {
            e.set_unprotected(fields::TITLE, "Changed");
        })
        .unwrap();

        let entry = root.find_entry_by_uuid(direct_uuid).unwrap();
        assert_eq!(entry.uuid, direct_uuid);
    }

    #[test]
    fn update_entry_sets_modification_time() {
        let (mut root, direct_uuid, _, _) = make_group_tree();
        let meta = Meta::default();
        let before = Times::now();

        update_entry(&mut root, direct_uuid, &meta, |e| {
            e.set_unprotected(fields::TITLE, "Changed");
        })
        .unwrap();

        let entry = root.find_entry_by_uuid(direct_uuid).unwrap();
        assert!(entry.times.last_modification.unwrap() >= before);
    }

    #[test]
    fn read_entry_fields_includes_custom_data() {
        let mut entry = Entry::new();
        entry.set_unprotected(fields::TITLE, "OTP");
        entry.set_protected(fields::PASSWORD, "hunter2");
        entry.custom_data.insert(
            "otp".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String(
                    "otpauth://totp/ManyKee:test?secret=JBSWY3DPEHPK3PXP".to_string(),
                )),
                last_modification_time: None,
                unknown_xml: Vec::new(),
            },
        );

        let payload = read_entry_fields(&entry);
        assert_eq!(
            payload.fields.get(fields::TITLE).map(String::as_str),
            Some("OTP")
        );
        assert_eq!(
            payload.custom_data.get("otp").map(String::as_str),
            Some("otpauth://totp/ManyKee:test?secret=JBSWY3DPEHPK3PXP")
        );
        assert_eq!(payload.protected.get(fields::TITLE), Some(&false));
        assert_eq!(payload.protected.get(fields::PASSWORD), Some(&true));
    }

    #[test]
    fn move_entry_preserves_last_modification_and_history() {
        let (mut root, direct_uuid, _, child_uuid) = make_group_tree();
        update_entry(&mut root, direct_uuid, &Meta::default(), |entry| {
            entry.set_unprotected(fields::USERNAME, "before-move");
        })
        .unwrap();
        let before = root
            .find_entry_by_uuid(direct_uuid)
            .unwrap()
            .times
            .last_modification;
        let history_len = root
            .find_entry_by_uuid(direct_uuid)
            .unwrap()
            .history
            .as_ref()
            .unwrap()
            .get_entries()
            .len();

        move_entry(&mut root, direct_uuid, child_uuid).unwrap();

        let moved = root.find_entry_by_uuid(direct_uuid).unwrap();
        assert_eq!(moved.times.last_modification, before);
        assert_eq!(
            moved.history.as_ref().unwrap().get_entries().len(),
            history_len
        );
        assert_eq!(moved.previous_parent_group, Some(root.uuid));
    }

    #[test]
    fn move_entry_missing_target_group_fails() {
        let (mut root, direct_uuid, _, _) = make_group_tree();
        let error = move_entry(&mut root, direct_uuid, Uuid::new_v4()).unwrap_err();
        assert!(matches!(error, KeePassXcError::GroupNotFound(_)));
    }

    #[test]
    fn read_entry_totp_payload_is_deterministic() {
        let mut entry = Entry::new();
        entry.custom_data.insert(
            "otp".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String(
                    "otpauth://totp/test?secret=GEZDGNBVGY======&period=30&digits=6&algorithm=SHA1"
                        .to_string(),
                )),
                last_modification_time: None,
                unknown_xml: Vec::new(),
            },
        );

        let payload = read_entry_totp_at(&entry, 1234)
            .expect("totp payload should parse")
            .expect("entry should have totp");
        assert_eq!(payload.code, "528010");
        assert_eq!(payload.valid_for, 26);
        assert_eq!(payload.period, 30);
    }
}
