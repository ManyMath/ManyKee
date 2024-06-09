//! Entry CRUD traits and history-aware updates.

use keepass::db::{Entry, Group, History, Meta, Times, Value};
use uuid::Uuid;

use crate::error::KeePassXcError;

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

 let mut snapshot = entry.clone();
 snapshot.history.take();

 updater(entry);

 entry.times.last_modification = Some(Times::now());

 if entry.history.is_none() {
 entry.history = Some(History::default());
 }
 entry.history.as_mut().unwrap().add_entry(snapshot);

 if let Some(max) = meta.history_max_items {
 if max > 0 {
 let max = max as usize;
 let history = entry.history.as_mut().unwrap();
 let entries = history.get_entries();
 if entries.len() > max {
 let mut owned = entries.clone();
 owned.truncate(max);
 let mut new_history = History::default();
 for e in owned.into_iter().rev() {
 new_history.add_entry(e);
 }
 entry.history = Some(new_history);
 }
 }
 }

 if let Some(max_bytes) = meta.history_max_size {
 if max_bytes > 0 {
 let max_bytes = max_bytes as usize;
 loop {
 let history = entry.history.as_ref().unwrap();
 if history.get_entries().len() <= 1 || estimate_history_size(history) <= max_bytes {
 break;
 }
 let mut entries = history.get_entries().clone();
 entries.pop();
 let mut new_history = History::default();
 for e in entries.into_iter().rev() {
 new_history.add_entry(e);
 }
 entry.history = Some(new_history);
 }
 }
 }

 Ok(())
}

/// Estimate the size of all entries in a History for max-size enforcement.
fn estimate_history_size(history: &History) -> usize {
 history
 .get_entries()
 .iter()
 .map(|e| estimate_entry_size(e))
 .sum()
}

/// Approximate size of an entry: sum of all field string lengths + attachment sizes.
fn estimate_entry_size(entry: &Entry) -> usize {
 let field_size: usize = entry
 .fields
 .iter()
 .map(|(k, v)| k.len() + v.get().len())
 .sum();
 let attachment_size: usize = entry
 .attachments
 .iter()
 .map(|(k, a)| k.len() + a.data.get().len())
 .sum();
 field_size + attachment_size
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
 use keepass::db::{fields, Entry, Group, Meta};

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
}
