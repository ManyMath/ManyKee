//! Recycle bin management with soft/hard delete and DeletedObjects tracking.

use keepass::db::{Database, Group, Times};
use uuid::Uuid;

use crate::entry::EntryExt;
use crate::error::KeePassXcError;
use crate::group::GroupExt;

/// Recursively collect all entry and subgroup UUIDs within a group.
fn collect_all_uuids(group: &Group) -> Vec<Uuid> {
    let mut uuids = Vec::new();
    for entry in &group.entries {
        uuids.push(entry.uuid);
    }
    for subgroup in &group.groups {
        uuids.push(subgroup.uuid);
        uuids.extend(collect_all_uuids(subgroup));
    }
    uuids
}

pub fn get_or_create_recycle_bin(db: &mut Database) -> Result<Uuid, KeePassXcError> {
    match db.meta.recyclebin_enabled {
        Some(false) | None => return Err(KeePassXcError::RecycleBinDisabled),
        _ => {}
    }

    if let Some(uuid) = db.meta.recyclebin_uuid {
        if !uuid.is_nil() && db.root.find_group_by_uuid(uuid).is_some() {
            return Ok(uuid);
        }
    }

    let mut bin = Group::new("Recycle Bin");
    bin.icon_id = Some(43);
    bin.enable_searching = Some(false);
    let bin_uuid = bin.uuid;

    db.meta.recyclebin_uuid = Some(bin_uuid);
    db.meta.recyclebin_changed = Some(Times::now());
    db.root.add_group(bin);

    Ok(bin_uuid)
}

pub fn delete_entry(db: &mut Database, uuid: Uuid, soft: bool) -> Result<(), KeePassXcError> {
    // Resolve (or create) the recycle bin *before* unlinking the entry, so a
    // disabled recycle bin errors out without having removed anything.
    let bin_uuid = if soft {
        Some(get_or_create_recycle_bin(db)?)
    } else {
        None
    };

    let entry = db
        .root
        .remove_entry(uuid)
        .ok_or(KeePassXcError::EntryNotFound(uuid))?;

    let now = Times::now();
    db.deleted_objects.insert(uuid, Some(now));

    if let Some(bin_uuid) = bin_uuid {
        let bin = db
            .root
            .find_group_by_uuid_mut(bin_uuid)
            .expect("recycle bin group must exist after get_or_create");
        bin.add_entry(entry);
    }

    Ok(())
}

pub fn delete_group(db: &mut Database, uuid: Uuid, soft: bool) -> Result<(), KeePassXcError> {
    if uuid == db.root.uuid {
        return Err(KeePassXcError::GroupNotFound(uuid));
    }

    // Resolve (or create) the recycle bin *before* unlinking the group, so a
    // disabled recycle bin errors out without having removed anything.
    let bin_uuid = if soft {
        if let Some(bin_uuid) = db.meta.recyclebin_uuid {
            if !bin_uuid.is_nil() {
                let target = db
                    .root
                    .find_group_by_uuid(uuid)
                    .ok_or(KeePassXcError::GroupNotFound(uuid))?;
                // Rejects both uuid == bin_uuid (find_group_by_uuid matches self)
                // and uuid being an ancestor of the recycle bin.
                if target.find_group_by_uuid(bin_uuid).is_some() {
                    return Err(KeePassXcError::GroupNotFound(uuid));
                }
            }
        }
        Some(get_or_create_recycle_bin(db)?)
    } else {
        None
    };

    let removed = db
        .root
        .remove_group(uuid)
        .ok_or(KeePassXcError::GroupNotFound(uuid))?;

    let now = Times::now();

    db.deleted_objects.insert(uuid, Some(now));

    if let Some(bin_uuid) = bin_uuid {
        let bin = db
            .root
            .find_group_by_uuid_mut(bin_uuid)
            .expect("recycle bin group must exist after get_or_create");
        bin.add_group(removed);
    } else {
        for descendant_uuid in collect_all_uuids(&removed) {
            db.deleted_objects.insert(descendant_uuid, Some(now));
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use keepass::config::DatabaseConfig;
    use keepass::db::{fields, Database, Entry, Group};

    /// Create a test database with recyclebin_enabled=true
    fn make_db() -> Database {
        let mut db = Database::new(DatabaseConfig::default());
        db.meta.recyclebin_enabled = Some(true);
        db
    }

    fn make_entry(title: &str) -> Entry {
        let mut e = Entry::new();
        e.set_unprotected(fields::TITLE, title);
        e
    }

    #[test]
    fn get_or_create_bin_disabled_returns_error() {
        let mut db = Database::new(DatabaseConfig::default());
        db.meta.recyclebin_enabled = Some(false);
        let result = get_or_create_recycle_bin(&mut db);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            KeePassXcError::RecycleBinDisabled
        ));
    }

    #[test]
    fn get_or_create_bin_none_returns_error() {
        let mut db = Database::new(DatabaseConfig::default());
        // recyclebin_enabled is None by default
        let result = get_or_create_recycle_bin(&mut db);
        assert!(result.is_err());
    }

    #[test]
    fn get_or_create_bin_creates_new() {
        let mut db = make_db();
        let result = get_or_create_recycle_bin(&mut db);
        assert!(result.is_ok());
        let bin_uuid = result.unwrap();

        // Verify bin was created with correct properties
        let bin = db.root.find_group_by_uuid(bin_uuid).unwrap();
        assert_eq!(bin.name, "Recycle Bin");
        assert_eq!(bin.icon_id, Some(43));
        assert_eq!(bin.enable_searching, Some(false));

        // Verify meta was updated
        assert_eq!(db.meta.recyclebin_uuid, Some(bin_uuid));
        assert!(db.meta.recyclebin_changed.is_some());
    }

    #[test]
    fn get_or_create_bin_returns_existing() {
        let mut db = make_db();
        let first = get_or_create_recycle_bin(&mut db).unwrap();
        let second = get_or_create_recycle_bin(&mut db).unwrap();
        assert_eq!(first, second);
        // Should not have created a second bin group
        let bin_count = db
            .root
            .groups
            .iter()
            .filter(|g| g.name == "Recycle Bin")
            .count();
        assert_eq!(bin_count, 1);
    }

    #[test]
    fn soft_delete_entry_moves_to_bin() {
        let mut db = make_db();
        let entry = make_entry("ToDelete");
        let uuid = entry.uuid;
        db.root.entries.push(entry);

        let result = delete_entry(&mut db, uuid, true);
        assert!(result.is_ok());

        // Entry should no longer be in root directly
        assert!(db.root.entries.iter().all(|e| e.uuid != uuid));

        // Entry should be in recycle bin
        let bin_uuid = db.meta.recyclebin_uuid.unwrap();
        let bin = db.root.find_group_by_uuid(bin_uuid).unwrap();
        assert!(bin.entries.iter().any(|e| e.uuid == uuid));

        // DeletedObject should be recorded
        assert!(db.deleted_objects.contains_key(&uuid));
        assert!(db.deleted_objects[&uuid].is_some());
    }

    #[test]
    fn soft_delete_entry_auto_creates_bin() {
        let mut db = make_db();
        assert!(db.meta.recyclebin_uuid.is_none());

        let entry = make_entry("ToDelete");
        let uuid = entry.uuid;
        db.root.entries.push(entry);

        delete_entry(&mut db, uuid, true).unwrap();

        // Bin should have been auto-created
        assert!(db.meta.recyclebin_uuid.is_some());
        let bin_uuid = db.meta.recyclebin_uuid.unwrap();
        let bin = db.root.find_group_by_uuid(bin_uuid).unwrap();
        assert_eq!(bin.name, "Recycle Bin");
    }

    #[test]
    fn soft_delete_entry_not_found() {
        let mut db = make_db();
        let result = delete_entry(&mut db, Uuid::new_v4(), true);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            KeePassXcError::EntryNotFound(_)
        ));
    }

    #[test]
    fn hard_delete_entry_removes_entirely() {
        let mut db = make_db();
        let entry = make_entry("ToDelete");
        let uuid = entry.uuid;
        db.root.entries.push(entry);

        let result = delete_entry(&mut db, uuid, false);
        assert!(result.is_ok());

        // Entry should be gone from entire tree
        assert!(db.root.find_entry_by_uuid(uuid).is_none());

        // DeletedObject should still be recorded
        assert!(db.deleted_objects.contains_key(&uuid));
    }

    #[test]
    fn hard_delete_entry_not_found() {
        let mut db = make_db();
        let result = delete_entry(&mut db, Uuid::new_v4(), false);
        assert!(result.is_err());
    }

    #[test]
    fn soft_delete_group_moves_to_bin() {
        let mut db = make_db();
        let mut group = Group::new("MyGroup");
        let entry = make_entry("GroupEntry");
        let entry_uuid = entry.uuid;
        group.entries.push(entry);
        let group_uuid = group.uuid;
        db.root.groups.push(group);

        let result = delete_group(&mut db, group_uuid, true);
        assert!(result.is_ok());

        // Group should be in recycle bin
        let bin_uuid = db.meta.recyclebin_uuid.unwrap();
        let bin = db.root.find_group_by_uuid(bin_uuid).unwrap();
        assert!(bin.groups.iter().any(|g| g.uuid == group_uuid));

        // The group's entries should still be intact inside it
        let moved_group = bin.groups.iter().find(|g| g.uuid == group_uuid).unwrap();
        assert!(moved_group.entries.iter().any(|e| e.uuid == entry_uuid));

        // Only the group UUID is recorded as DeletedObject (not entries within it)
        assert!(db.deleted_objects.contains_key(&group_uuid));
    }

    #[test]
    fn soft_delete_group_not_found() {
        let mut db = make_db();
        let result = delete_group(&mut db, Uuid::new_v4(), true);
        assert!(result.is_err());
    }

    #[test]
    fn hard_delete_group_removes_entirely_and_records_descendants() {
        let mut db = make_db();
        let mut group = Group::new("MyGroup");
        let entry = make_entry("GroupEntry");
        let entry_uuid = entry.uuid;
        let mut subgroup = Group::new("SubGroup");
        let sub_entry = make_entry("SubEntry");
        let sub_entry_uuid = sub_entry.uuid;
        subgroup.entries.push(sub_entry);
        let subgroup_uuid = subgroup.uuid;
        group.groups.push(subgroup);
        group.entries.push(entry);
        let group_uuid = group.uuid;
        db.root.groups.push(group);

        let result = delete_group(&mut db, group_uuid, false);
        assert!(result.is_ok());

        // Group should be gone
        assert!(db.root.find_group_by_uuid(group_uuid).is_none());

        // DeletedObjects for group, subgroup, and all entries
        assert!(db.deleted_objects.contains_key(&group_uuid));
        assert!(db.deleted_objects.contains_key(&entry_uuid));
        assert!(db.deleted_objects.contains_key(&subgroup_uuid));
        assert!(db.deleted_objects.contains_key(&sub_entry_uuid));
    }

    #[test]
    fn cannot_delete_root_group() {
        let mut db = make_db();
        let root_uuid = db.root.uuid;

        let result = delete_group(&mut db, root_uuid, true);
        assert!(result.is_err());

        let result = delete_group(&mut db, root_uuid, false);
        assert!(result.is_err());
    }

    #[test]
    fn cannot_soft_delete_recycle_bin() {
        let mut db = make_db();
        let bin_uuid = get_or_create_recycle_bin(&mut db).unwrap();

        let result = delete_group(&mut db, bin_uuid, true);
        assert!(result.is_err());
    }

    #[test]
    fn cannot_soft_delete_ancestor_of_recycle_bin() {
        let mut db = make_db();
        let bin_uuid = get_or_create_recycle_bin(&mut db).unwrap();

        // Move the recycle bin under a new "Ancestor" group.
        let mut ancestor = Group::new("Ancestor");
        let bin = db.root.remove_group(bin_uuid).unwrap();
        let ancestor_uuid = ancestor.uuid;
        ancestor.groups.push(bin);
        db.root.groups.push(ancestor);

        // Soft-deleting the ancestor would detach the live recycle bin along
        // with it, so it must be rejected just like deleting the bin itself.
        let result = delete_group(&mut db, ancestor_uuid, true);
        assert!(result.is_err());
        assert!(db.root.find_group_by_uuid(ancestor_uuid).is_some());
        assert!(db.root.find_group_by_uuid(bin_uuid).is_some());
    }

    #[test]
    fn can_hard_delete_recycle_bin() {
        let mut db = make_db();
        let bin_uuid = get_or_create_recycle_bin(&mut db).unwrap();

        // Hard deleting the recycle bin should work (e.g., user wants to purge it)
        let result = delete_group(&mut db, bin_uuid, false);
        assert!(result.is_ok());
        assert!(db.root.find_group_by_uuid(bin_uuid).is_none());
        assert!(db.deleted_objects.contains_key(&bin_uuid));
    }

    #[test]
    fn deleted_object_has_timestamp() {
        let mut db = make_db();
        let entry = make_entry("Test");
        let uuid = entry.uuid;
        db.root.entries.push(entry);

        let before = Times::now();
        delete_entry(&mut db, uuid, false).unwrap();

        let deletion_time = db.deleted_objects[&uuid].unwrap();
        assert!(deletion_time >= before);
    }

    #[test]
    fn soft_delete_entry_with_recycle_bin_disabled_does_not_lose_entry() {
        let mut db = Database::new(DatabaseConfig::default());
        db.meta.recyclebin_enabled = Some(false);
        let entry = make_entry("ToDelete");
        let uuid = entry.uuid;
        db.root.entries.push(entry);

        let result = delete_entry(&mut db, uuid, true);
        assert!(result.is_err());

        // The entry must still be intact in the tree, not silently lost.
        assert!(db.root.entries.iter().any(|e| e.uuid == uuid));
        assert!(!db.deleted_objects.contains_key(&uuid));
    }

    #[test]
    fn soft_delete_group_with_recycle_bin_disabled_does_not_lose_group() {
        let mut db = Database::new(DatabaseConfig::default());
        db.meta.recyclebin_enabled = Some(false);
        let group = Group::new("ToDelete");
        let group_uuid = group.uuid;
        db.root.groups.push(group);

        let result = delete_group(&mut db, group_uuid, true);
        assert!(result.is_err());

        // The group must still be intact in the tree, not silently lost.
        assert!(db.root.find_group_by_uuid(group_uuid).is_some());
        assert!(!db.deleted_objects.contains_key(&group_uuid));
    }

    #[test]
    fn collect_all_uuids_recursive() {
        let mut group = Group::new("Parent");
        let entry1 = make_entry("E1");
        let entry2 = make_entry("E2");
        let mut sub = Group::new("Sub");
        let entry3 = make_entry("E3");

        let e1_uuid = entry1.uuid;
        let e2_uuid = entry2.uuid;
        let e3_uuid = entry3.uuid;
        let sub_uuid = sub.uuid;

        sub.entries.push(entry3);
        group.entries.push(entry1);
        group.entries.push(entry2);
        group.groups.push(sub);

        let uuids = collect_all_uuids(&group);
        assert!(uuids.contains(&e1_uuid));
        assert!(uuids.contains(&e2_uuid));
        assert!(uuids.contains(&e3_uuid));
        assert!(uuids.contains(&sub_uuid));
        assert_eq!(uuids.len(), 4);
    }
}
