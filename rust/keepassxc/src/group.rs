//! Group CRUD extension traits.

use std::io::Error;

use keepass::db::Group;
use uuid::Uuid;

use crate::{KeePassXcError, Times};

/// Extension trait for group CRUD operations on a Group tree.
pub trait GroupExt {
    /// Find a group by UUID anywhere in the group tree (recursive, includes self).
    fn find_group_by_uuid(&self, uuid: Uuid) -> Option<&Group>;
    /// Find a group by UUID (mutable, recursive, includes self).
    fn find_group_by_uuid_mut(&mut self, uuid: Uuid) -> Option<&mut Group>;
    /// Add a child group to this group.
    fn add_group(&mut self, group: Group);
    /// Remove a child group by UUID from anywhere in the tree.
    /// Does NOT match self -- only searches children.
    /// Returns the removed group with all its entries and subgroups.
    fn remove_group(&mut self, uuid: Uuid) -> Option<Group>;
}

/// Create a child group under `parent_uuid`.
pub fn create_group(
    root: &mut Group,
    parent_uuid: Uuid,
    name: &str,
) -> Result<Uuid, KeePassXcError> {
    let parent = root
        .find_group_by_uuid_mut(parent_uuid)
        .ok_or(KeePassXcError::GroupNotFound(parent_uuid))?;
    let group = Group::new(name);
    let uuid = group.uuid;
    parent.add_group(group);
    Ok(uuid)
}

/// Rename a group by UUID.
pub fn rename_group(root: &mut Group, group_uuid: Uuid, name: &str) -> Result<(), KeePassXcError> {
    let group = root
        .find_group_by_uuid_mut(group_uuid)
        .ok_or(KeePassXcError::GroupNotFound(group_uuid))?;
    group.name = name.to_string();
    Ok(())
}

/// Move a group to a new parent with an O(n) tree traversal.
///
/// The full subtree moves intact. This updates move bookkeeping via
/// `previous_parent_group` and `location_changed` without touching the group's
/// last modification timestamp.
pub fn move_group(
    root: &mut Group,
    group_uuid: Uuid,
    target_parent_uuid: Uuid,
) -> Result<(), KeePassXcError> {
    if group_uuid == root.uuid {
        return Err(invalid_move("cannot move the root group"));
    }
    if group_uuid == target_parent_uuid {
        return Err(invalid_move("cannot move a group into itself"));
    }

    let source_parent_uuid = find_group_parent_uuid(root, group_uuid)
        .ok_or(KeePassXcError::GroupNotFound(group_uuid))?;
    let source_group = root
        .find_group_by_uuid(group_uuid)
        .ok_or(KeePassXcError::GroupNotFound(group_uuid))?;
    if source_group
        .find_group_by_uuid(target_parent_uuid)
        .is_some()
    {
        return Err(invalid_move(
            "cannot move a group into one of its descendants",
        ));
    }
    if root.find_group_by_uuid(target_parent_uuid).is_none() {
        return Err(KeePassXcError::GroupNotFound(target_parent_uuid));
    }
    if source_parent_uuid == target_parent_uuid {
        return Ok(());
    }

    let (mut group, _) =
        take_group(root, group_uuid).ok_or(KeePassXcError::GroupNotFound(group_uuid))?;
    group.previous_parent_group = Some(source_parent_uuid);
    group.times.location_changed = Some(Times::now());

    let target_parent = root
        .find_group_by_uuid_mut(target_parent_uuid)
        .ok_or(KeePassXcError::GroupNotFound(target_parent_uuid))?;
    target_parent.add_group(group);
    Ok(())
}

impl GroupExt for Group {
    fn find_group_by_uuid(&self, uuid: Uuid) -> Option<&Group> {
        self.group_by_uuid(uuid)
    }

    fn find_group_by_uuid_mut(&mut self, uuid: Uuid) -> Option<&mut Group> {
        self.group_by_uuid_mut(uuid)
    }

    fn add_group(&mut self, group: Group) {
        self.groups.push(group);
    }

    fn remove_group(&mut self, uuid: Uuid) -> Option<Group> {
        // Check direct children first
        if let Some(pos) = self.groups.iter().position(|g| g.uuid == uuid) {
            return Some(self.groups.remove(pos));
        }
        // Recurse into child groups
        for group in &mut self.groups {
            if let Some(removed) = group.remove_group(uuid) {
                return Some(removed);
            }
        }
        None
    }
}

fn invalid_move(message: &str) -> KeePassXcError {
    KeePassXcError::Io(Error::other(message))
}

fn find_group_parent_uuid(group: &Group, target_uuid: Uuid) -> Option<Uuid> {
    if group.groups.iter().any(|child| child.uuid == target_uuid) {
        return Some(group.uuid);
    }
    for child in &group.groups {
        if let Some(parent_uuid) = find_group_parent_uuid(child, target_uuid) {
            return Some(parent_uuid);
        }
    }
    None
}

fn take_group(group: &mut Group, target_uuid: Uuid) -> Option<(Group, Uuid)> {
    if let Some(position) = group
        .groups
        .iter()
        .position(|child| child.uuid == target_uuid)
    {
        return Some((group.groups.remove(position), group.uuid));
    }
    for child in &mut group.groups {
        if let Some(found) = take_group(child, target_uuid) {
            return Some(found);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use keepass::db::Group;

    fn make_group_tree() -> (Group, Uuid, Uuid, Uuid) {
        // root -> child -> grandchild
        let mut root = Group::new("Root");
        let mut child = Group::new("Child");
        let grandchild = Group::new("Grandchild");

        let root_uuid = root.uuid;
        let child_uuid = child.uuid;
        let grandchild_uuid = grandchild.uuid;

        child.groups.push(grandchild);
        root.groups.push(child);

        (root, root_uuid, child_uuid, grandchild_uuid)
    }

    #[test]
    fn find_group_self() {
        let (root, root_uuid, _, _) = make_group_tree();
        let found = root.find_group_by_uuid(root_uuid);
        assert!(found.is_some());
        assert_eq!(found.unwrap().uuid, root_uuid);
    }

    #[test]
    fn find_group_child() {
        let (root, _, child_uuid, _) = make_group_tree();
        let found = root.find_group_by_uuid(child_uuid);
        assert!(found.is_some());
        assert_eq!(found.unwrap().uuid, child_uuid);
    }

    #[test]
    fn find_group_grandchild() {
        let (root, _, _, grandchild_uuid) = make_group_tree();
        let found = root.find_group_by_uuid(grandchild_uuid);
        assert!(found.is_some());
        assert_eq!(found.unwrap().uuid, grandchild_uuid);
    }

    #[test]
    fn find_group_not_found() {
        let (root, _, _, _) = make_group_tree();
        assert!(root.find_group_by_uuid(Uuid::new_v4()).is_none());
    }

    #[test]
    fn find_group_mut_works() {
        let (mut root, _, child_uuid, _) = make_group_tree();
        let found = root.find_group_by_uuid_mut(child_uuid);
        assert!(found.is_some());
        assert_eq!(found.unwrap().uuid, child_uuid);
    }

    #[test]
    fn add_group_to_parent() {
        let mut parent = Group::new("Parent");
        let child = Group::new("NewChild");
        let uuid = child.uuid;
        parent.add_group(child);
        assert_eq!(parent.groups.len(), 1);
        assert_eq!(parent.groups[0].uuid, uuid);
    }

    #[test]
    fn remove_group_direct_child() {
        let (mut root, _, child_uuid, _) = make_group_tree();
        let removed = root.remove_group(child_uuid);
        assert!(removed.is_some());
        assert_eq!(removed.unwrap().uuid, child_uuid);
        assert!(root.find_group_by_uuid(child_uuid).is_none());
    }

    #[test]
    fn remove_group_nested() {
        let (mut root, _, _, grandchild_uuid) = make_group_tree();
        let removed = root.remove_group(grandchild_uuid);
        assert!(removed.is_some());
        assert_eq!(removed.unwrap().uuid, grandchild_uuid);
        assert!(root.find_group_by_uuid(grandchild_uuid).is_none());
    }

    #[test]
    fn remove_group_not_found() {
        let (mut root, _, _, _) = make_group_tree();
        assert!(root.remove_group(Uuid::new_v4()).is_none());
    }

    #[test]
    fn remove_group_does_not_remove_self() {
        let (mut root, root_uuid, _, _) = make_group_tree();
        // remove_group should NOT match self
        assert!(root.remove_group(root_uuid).is_none());
        // root should still exist
        assert_eq!(root.uuid, root_uuid);
    }

    #[test]
    fn remove_group_preserves_uuid() {
        let (mut root, _, child_uuid, _) = make_group_tree();
        let removed = root.remove_group(child_uuid).unwrap();
        assert_eq!(removed.uuid, child_uuid);
    }

    #[test]
    fn remove_group_preserves_subtree() {
        let (mut root, _, child_uuid, grandchild_uuid) = make_group_tree();
        let removed = root.remove_group(child_uuid).unwrap();
        // The removed group should still contain its grandchild
        assert_eq!(removed.groups.len(), 1);
        assert_eq!(removed.groups[0].uuid, grandchild_uuid);
    }

    #[test]
    fn create_group_under_parent() {
        let (mut root, _, child_uuid, _) = make_group_tree();
        let new_uuid = create_group(&mut root, child_uuid, "Created").unwrap();
        let created = root.find_group_by_uuid(new_uuid).unwrap();
        assert_eq!(created.name, "Created");
    }

    #[test]
    fn rename_group_updates_name() {
        let (mut root, _, child_uuid, _) = make_group_tree();
        rename_group(&mut root, child_uuid, "Renamed").unwrap();
        assert_eq!(root.find_group_by_uuid(child_uuid).unwrap().name, "Renamed");
    }

    #[test]
    fn move_group_preserves_subtree() {
        let (mut root, root_uuid, child_uuid, grandchild_uuid) = make_group_tree();
        let target_uuid = create_group(&mut root, root_uuid, "Target").unwrap();
        move_group(&mut root, child_uuid, target_uuid).unwrap();

        let moved = root.find_group_by_uuid(child_uuid).unwrap();
        assert_eq!(moved.previous_parent_group, Some(root_uuid));
        assert!(moved.find_group_by_uuid(grandchild_uuid).is_some());
    }

    #[test]
    fn move_group_into_self_fails() {
        let (mut root, _, child_uuid, _) = make_group_tree();
        let error = move_group(&mut root, child_uuid, child_uuid).unwrap_err();
        assert!(matches!(error, KeePassXcError::Io(_)));
        assert!(error.to_string().contains("itself"));
    }

    #[test]
    fn move_group_into_descendant_fails() {
        let (mut root, _, child_uuid, grandchild_uuid) = make_group_tree();
        let error = move_group(&mut root, child_uuid, grandchild_uuid).unwrap_err();
        assert!(matches!(error, KeePassXcError::Io(_)));
        assert!(error.to_string().contains("descendants"));
    }
}
