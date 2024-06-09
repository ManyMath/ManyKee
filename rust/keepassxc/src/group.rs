//! Group CRUD extension traits.

use keepass::db::Group;
use uuid::Uuid;

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
}
