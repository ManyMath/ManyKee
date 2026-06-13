use std::collections::{HashMap, VecDeque};

use crate::db::{Database, Entry, Group, History, Times};
use chrono::NaiveDateTime;
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub enum MergeEventType {
    EntryCreated,
    EntryDeleted,
    EntryLocationUpdated,
    EntryUpdated,

    GroupCreated,
    GroupDeleted,
    GroupLocationUpdated,
    GroupUpdated,
}

#[derive(Debug, Clone)]
pub struct MergeEvent {
    /// The uuid of the node (entry or group) affected by
    /// the merge event.
    pub node_uuid: Uuid,

    pub event_type: MergeEventType,
}

#[derive(Debug, Default, Clone)]
pub struct MergeLog {
    pub warnings: Vec<String>,
    pub events: Vec<MergeEvent>,
}

/// Errors while merge two databases
#[derive(Error, Debug)]
pub enum MergeError {
    #[error("{0}")]
    GenericError(String),

    #[error("Could not find group {0}")]
    FindGroupError(Uuid),

    #[error("Could not find entry {0}")]
    FindEntryError(Uuid),

    #[error("Entries with UUID {0} have the same modification time but have diverged.")]
    EntryModificationTimeNotUpdated(String),

    #[error("Groups with UUID {0} have the same modification time but have diverged.")]
    GroupModificationTimeNotUpdated(String),
}

impl MergeLog {
    pub fn merge_with(&self, other: &MergeLog) -> MergeLog {
        let mut response = MergeLog::default();
        response.warnings.append(self.warnings.clone().as_mut());
        response.warnings.append(other.warnings.clone().as_mut());
        response.events.append(self.events.clone().as_mut());
        response.events.append(other.events.clone().as_mut());
        response
    }

    pub fn append(&mut self, other: &MergeLog) {
        self.warnings.append(other.warnings.clone().as_mut());
        self.events.append(other.events.clone().as_mut());
    }
}

impl Database {
    /// Merge this database with another version of this same database.
    /// This function will use the UUIDs to detect that entries and groups are
    /// the same.
    pub fn merge(&mut self, other: &Database) -> Result<MergeLog, MergeError> {
        let mut log = MergeLog::default();
        log.append(&self.merge_group(&other.root, false)?);
        log.append(&self.merge_deletions(other)?);
        self.merge_custom_icons(other);
        self.merge_meta(other);
        Ok(log)
    }

    /// Merge `other`'s `Meta` into `self`'s, field by field. Fields that
    /// carry their own "last changed" timestamp (name, description, default
    /// username, recycle bin settings, entry templates group) take whichever
    /// side is newer. Fields with no timestamp of their own (generator,
    /// memory protection, history limits, maintenance/master-key settings,
    /// preserved unknown XML) are governed by `settings_changed`, mirroring
    /// how KeePassXC itself scopes that timestamp. `custom_data` is unioned,
    /// with same-key collisions resolved per item by
    /// `last_modification_time`.
    fn merge_meta(&mut self, other: &Database) {
        fn newer(self_time: Option<NaiveDateTime>, other_time: Option<NaiveDateTime>) -> bool {
            match (self_time, other_time) {
                (Some(s), Some(o)) => o > s,
                (None, Some(_)) => true,
                _ => false,
            }
        }

        let self_meta = &mut self.meta;
        let other_meta = &other.meta;

        if newer(self_meta.database_name_changed, other_meta.database_name_changed) {
            self_meta.database_name = other_meta.database_name.clone();
            self_meta.database_name_changed = other_meta.database_name_changed;
        }

        if newer(
            self_meta.database_description_changed,
            other_meta.database_description_changed,
        ) {
            self_meta.database_description = other_meta.database_description.clone();
            self_meta.database_description_changed = other_meta.database_description_changed;
        }

        if newer(self_meta.default_username_changed, other_meta.default_username_changed) {
            self_meta.default_username = other_meta.default_username.clone();
            self_meta.default_username_changed = other_meta.default_username_changed;
        }

        if newer(self_meta.recyclebin_changed, other_meta.recyclebin_changed) {
            self_meta.recyclebin_enabled = other_meta.recyclebin_enabled;
            self_meta.recyclebin_uuid = other_meta.recyclebin_uuid;
            self_meta.recyclebin_changed = other_meta.recyclebin_changed;
        }

        if newer(
            self_meta.entry_templates_group_changed,
            other_meta.entry_templates_group_changed,
        ) {
            self_meta.entry_templates_group = other_meta.entry_templates_group;
            self_meta.entry_templates_group_changed = other_meta.entry_templates_group_changed;
        }

        if newer(self_meta.settings_changed, other_meta.settings_changed) {
            self_meta.generator = other_meta.generator.clone();
            self_meta.maintenance_history_days = other_meta.maintenance_history_days;
            self_meta.color = other_meta.color.clone();
            self_meta.master_key_changed = other_meta.master_key_changed;
            self_meta.master_key_change_rec = other_meta.master_key_change_rec;
            self_meta.master_key_change_force = other_meta.master_key_change_force;
            self_meta.memory_protection = other_meta.memory_protection.clone();
            self_meta.history_max_items = other_meta.history_max_items;
            self_meta.history_max_size = other_meta.history_max_size;
            self_meta.last_selected_group = other_meta.last_selected_group;
            self_meta.last_top_visible_group = other_meta.last_top_visible_group;
            self_meta.unknown_xml = other_meta.unknown_xml.clone();
            self_meta.settings_changed = other_meta.settings_changed;
        }

        for (key, other_item) in &other_meta.custom_data {
            match self_meta.custom_data.get(key) {
                Some(self_item)
                    if !newer(self_item.last_modification_time, other_item.last_modification_time) =>
                {
                    // Destination's item is at least as new; keep it.
                }
                _ => {
                    self_meta.custom_data.insert(key.clone(), other_item.clone());
                }
            }
        }
    }

    /// Union custom icons from both databases.
    ///
    /// In the keepass-rs domain model, custom icon data is stored inline on
    /// entries as `custom_icon: Option<(Uuid, Vec<u8>)>`. After merging entries
    /// and groups, some entries in `self` may reference custom icon UUIDs
    /// (via `custom_icon`) that were copied from `other`. Those entries already
    /// carry their icon data. However, entries in `self` that were NOT updated
    /// from `other` might lack icon data if their `custom_icon` was `None` but
    /// a group references that icon UUID.
    ///
    /// This method collects all custom icon data from `other`'s entry tree and
    /// ensures that any entry in `self` with a matching `custom_icon` UUID has
    /// its data populated. This covers the case where icon data was only present
    /// in source entries that were not directly merged (e.g., older versions).
    fn merge_custom_icons(&mut self, other: &Database) {
        // Collect all custom icon (uuid -> data) from other's entry tree.
        let mut source_icons: HashMap<Uuid, Vec<u8>> = HashMap::new();
        Self::collect_custom_icons(&other.root, &mut source_icons);

        if source_icons.is_empty() {
            return;
        }

        // Ensure entries in self that reference custom icons have their data.
        Self::apply_custom_icons(&mut self.root, &source_icons);
    }

    fn collect_custom_icons(group: &Group, icons: &mut HashMap<Uuid, Vec<u8>>) {
        if let (Some(uuid), Some(data)) = (&group.custom_icon_uuid, &group.custom_icon_data) {
            icons.entry(*uuid).or_insert_with(|| data.clone());
        }
        for entry in &group.entries {
            if let Some((uuid, data)) = &entry.custom_icon {
                icons.entry(*uuid).or_insert_with(|| data.clone());
            }
            // Also check history entries for icon data.
            if let Some(history) = &entry.history {
                for h_entry in &history.entries {
                    if let Some((uuid, data)) = &h_entry.custom_icon {
                        icons.entry(*uuid).or_insert_with(|| data.clone());
                    }
                }
            }
        }
        for child in &group.groups {
            Self::collect_custom_icons(child, icons);
        }
    }

    fn apply_custom_icons(group: &mut Group, icons: &HashMap<Uuid, Vec<u8>>) {
        // If the group references a custom icon UUID but lacks its data, fill from source.
        if let Some(uuid) = &group.custom_icon_uuid {
            if group.custom_icon_data.is_none() {
                if let Some(source_data) = icons.get(uuid) {
                    group.custom_icon_data = Some(source_data.clone());
                }
            }
        }
        for entry in &mut group.entries {
            // If entry has a custom_icon UUID but no data, fill from source.
            if entry.custom_icon.is_none() {
                // Check if any source icon matches (no UUID to match against
                // since custom_icon is None). Skip.
            } else if let Some((uuid, data)) = &entry.custom_icon {
                if data.is_empty() {
                    if let Some(source_data) = icons.get(uuid) {
                        entry.custom_icon = Some((*uuid, source_data.clone()));
                    }
                }
            }
        }
        for child in &mut group.groups {
            Self::apply_custom_icons(child, icons);
        }
    }

    fn merge_deletions(&mut self, other: &Database) -> Result<MergeLog, MergeError> {
        // Utility function to search for a UUID in the VecDeque of deleted objects.
        let is_in_deleted_queue =
            |uuid: Uuid, deleted_groups_queue: &VecDeque<(Uuid, Option<NaiveDateTime>)>| -> bool {
                for (deleted_uuid, _) in deleted_groups_queue {
                    // This group still has a child group, but it is not going to be deleted.
                    if *deleted_uuid == uuid {
                        return true;
                    }
                }
                false
            };

        let mut log = MergeLog::default();

        let mut new_deleted_objects = self.deleted_objects.clone();

        // We start by deleting the entries, since we will only remove groups if they are empty.
        for (&other_uuid, &other_time) in &other.deleted_objects {
            if new_deleted_objects.contains_key(&other_uuid) {
                continue;
            }

            let Some(entry) = self.root.entry_by_uuid(other_uuid) else {
                // This uuid might refer to a group, which will be handled later.
                continue;
            };

            let parent_uuid = self
                .root
                .find_entry_parent(other_uuid)
                .ok_or(MergeError::FindEntryError(other_uuid))?;

            let entry_last_modification = match entry.times.last_modification {
                Some(t) => t,
                None => {
                    log.warnings.push(format!(
                        "Entry {} did not have a last modification timestamp",
                        entry.uuid
                    ));
                    Times::now()
                }
            };

            let other_time = other_time.unwrap_or_else(|| {
                log.warnings.push(format!(
                    "Entry {} did not have a last modification timestamp",
                    other_uuid
                ));
                Times::epoch()
            });

            let parent_group = self
                .root
                .group_by_uuid_mut(parent_uuid)
                .ok_or(MergeError::FindGroupError(parent_uuid))?;

            if entry_last_modification < other_time {
                parent_group.remove_entry(other_uuid)?;
                log.events.push(MergeEvent {
                    event_type: MergeEventType::EntryDeleted,
                    node_uuid: other_uuid,
                });

                new_deleted_objects.insert(other_uuid, Some(other_time));
            }
        }

        let mut deleted_groups_queue: VecDeque<(Uuid, Option<NaiveDateTime>)> = VecDeque::new();
        for (&deleted_uuid, &deleted_time) in &other.deleted_objects {
            if new_deleted_objects.contains_key(&deleted_uuid) {
                continue;
            }
            deleted_groups_queue.push_back((deleted_uuid, deleted_time));
        }

        while !deleted_groups_queue.is_empty() {
            let (deleted_uuid, deleted_time) = deleted_groups_queue.pop_front().unwrap();
            if new_deleted_objects.contains_key(&deleted_uuid) {
                continue;
            }

            let Some(parent_uuid) = self.root.find_group_parent(deleted_uuid) else {
                // The node might be an entry, since we didn't necessarily removed all the
                // entries that were in the deleted objects of the source database.
                continue;
            };

            let Some(group) = self.root.group_by_uuid_mut(deleted_uuid) else {
                // The node might be an entry, since we didn't necessarily removed all the
                // entries that were in the deleted objects of the source database.
                continue;
            };

            // Not deleting a group if it still has entries.
            if !group.entries.is_empty() {
                continue;
            }

            // This group still has a child group that might get deleted in the future, so we delay
            // decision to delete it or not.
            if !group
                .groups
                .iter()
                .filter(|g| is_in_deleted_queue(g.uuid, &deleted_groups_queue))
                .collect::<Vec<_>>()
                .is_empty()
            {
                deleted_groups_queue.push_back((deleted_uuid, deleted_time));
                continue;
            }

            // This group still a groups that won't be deleted, so we don't delete it.
            if !group.groups.is_empty() {
                continue;
            }

            let group_last_modification = match group.times.last_modification {
                Some(t) => t,
                None => {
                    log.warnings.push(format!(
                        "Group {} did not have a last modification timestamp",
                        group.uuid
                    ));
                    Times::now()
                }
            };

            let deleted_time = deleted_time.unwrap_or_else(|| {
                log.warnings.push(format!(
                    "Group {} did not have a deletion timestamp",
                    deleted_uuid
                ));
                Times::epoch()
            });

            if group_last_modification < deleted_time {
                let parent_group = self
                    .root
                    .group_by_uuid_mut(parent_uuid)
                    .ok_or(MergeError::FindGroupError(parent_uuid))?;

                parent_group.remove_group(deleted_uuid)?;
                log.events.push(MergeEvent {
                    event_type: MergeEventType::GroupDeleted,
                    node_uuid: deleted_uuid,
                });

                new_deleted_objects.insert(deleted_uuid, Some(deleted_time));
            }
        }

        self.deleted_objects = new_deleted_objects;
        Ok(log)
    }

    fn merge_group(
        &mut self,
        current_group: &Group,
        is_in_deleted_group: bool,
    ) -> Result<MergeLog, MergeError> {
        let mut log = MergeLog::default();

        // shallow merge the current group's data
        if let Some(destination_group) = self.root.group_by_uuid_mut(current_group.uuid) {
            let group_update_merge_events = destination_group.merge_with(current_group)?;
            log.append(&group_update_merge_events);
        }

        // merge entries by iterating over entries in source (aka current_group)
        for other_entry in &current_group.entries {
            // does the entry exist in the destination database?
            if let Some(existing_entry) = self.root.entry_by_uuid(other_entry.uuid).cloned() {
                let existing_parent = self.root.find_entry_parent(other_entry.uuid).unwrap();
                let mut existing_time = existing_entry.times.location_changed.clone();

                // is the location of the entry the same in both databases?
                if current_group.uuid != existing_parent && !is_in_deleted_group {
                    // we might have to relocate the entry, but we first check timestamps

                    let source_location_changed =
                        other_entry.times.location_changed.clone().unwrap_or_else(|| {
                            log.warnings.push(format!(
                                "Entry {} did not have a location updated timestamp",
                                other_entry.uuid
                            ));
                            Times::epoch()
                        });

                    let destination_location_changed =
                        existing_entry.times.location_changed.clone().unwrap_or_else(|| {
                            log.warnings.push(format!(
                                "Entry {} did not have a location updated timestamp",
                                other_entry.uuid
                            ));
                            Times::now()
                        });

                    // check location change timestamps to see if we need to relocate the entry
                    if source_location_changed > destination_location_changed {
                        // The entry was moved in the source database after it was moved in the
                        // destination database, so we have to move it to the new location.

                        log.events.push(MergeEvent {
                            event_type: MergeEventType::EntryLocationUpdated,
                            node_uuid: other_entry.uuid,
                        });

                        self.relocate_entry(
                            other_entry.uuid,
                            existing_parent,
                            current_group.uuid,
                            source_location_changed,
                        )?;

                        existing_time = Some(source_location_changed);
                    }
                }

                // skip updating entry data if it still matches
                if !existing_entry.has_diverged_from(other_entry) {
                    continue;
                }

                let (merged_entry, entry_merge_log) = existing_entry.merge(other_entry)?;
                let Some(merged_entry) = merged_entry else {
                    continue;
                };

                if existing_entry == merged_entry {
                    continue;
                }

                let existing_entry = self.root.entry_by_uuid_mut(other_entry.uuid).unwrap();
                *existing_entry = merged_entry.clone();

                if let Some(et) = existing_time {
                    existing_entry.times.location_changed = Some(et);
                }

                log.events.push(MergeEvent {
                    event_type: MergeEventType::EntryUpdated,
                    node_uuid: merged_entry.uuid,
                });

                log.append(&entry_merge_log);

                // the entry is now merged, we can skip the rest of the loop which is for processing new entries
                continue;
            }

            if self.deleted_objects.contains_key(&other_entry.uuid) {
                continue;
            }

            // We don't create new entries that exist under a deleted group.
            if is_in_deleted_group {
                continue;
            }

            // The entry doesn't exist in the destination, we create it
            let new_entry = other_entry.to_owned().clone();

            let new_entry_parent_group = self
                .root
                .group_by_uuid_mut(current_group.uuid)
                .ok_or(MergeError::FindGroupError(current_group.uuid))?;

            new_entry_parent_group.entries.push(new_entry.clone());

            // The entry's times (creation, last modification, location
            // changed, ...) are carried over unchanged from the source
            // database: this is the entry's first appearance in the
            // destination, so the source's own times are the authoritative
            // record of when it was created/modified/moved. This mirrors
            // how newly-created groups are handled just below.
            log.events.push(MergeEvent {
                event_type: MergeEventType::EntryCreated,
                node_uuid: new_entry.uuid,
            });
        }

        // merge groups by iterating over groups in source (aka current_group)
        for other_group in &current_group.groups {
            if self.deleted_objects.contains_key(&other_group.uuid) || is_in_deleted_group {
                let new_merge_log = self.merge_group(other_group, true)?;
                log.append(&new_merge_log);
                continue;
            }

            // does the group exist in the destination database?
            if let Some(existing_group) = self.root.group_by_uuid(other_group.uuid) {
                // `group_by_uuid` matches the root against itself, but
                // `find_group_parent` only ever finds parents of *children* -
                // it can never return a parent for the root. A malformed
                // source database where a non-root group shares the
                // destination's root UUID would otherwise panic here instead
                // of failing the merge cleanly.
                let existing_parent = self
                    .root
                    .find_group_parent(other_group.uuid)
                    .ok_or(MergeError::FindGroupError(other_group.uuid))?;

                if current_group.uuid != existing_parent {
                    // we might have to relocate the entry, but we first check timestamps

                    let source_location_changed_time =
                        other_group.times.location_changed.clone().unwrap_or_else(|| {
                            log.warnings.push(format!(
                                "Group {} did not have a location updated timestamp",
                                other_group.uuid
                            ));
                            Times::epoch()
                        });

                    let destination_location_changed_time =
                        existing_group.times.location_changed.clone().unwrap_or_else(|| {
                            log.warnings.push(format!(
                                "Group {} did not have a location updated timestamp",
                                other_group.uuid
                            ));
                            Times::now()
                        });

                    // check location change timestamps to see if we need to relocate the group
                    if source_location_changed_time > destination_location_changed_time {
                        log.events.push(MergeEvent {
                            event_type: MergeEventType::GroupLocationUpdated,
                            node_uuid: other_group.uuid,
                        });

                        self.relocate_group(
                            other_group.uuid,
                            existing_parent,
                            current_group.uuid,
                            source_location_changed_time,
                        )?;
                    }
                }

                // the group is now in the correct location, we can merge it with the current group
                let new_merge_log = self.merge_group(other_group, is_in_deleted_group)?;
                log.append(&new_merge_log);

                // the group is now merged, we can skip the rest of the loop which is for processing new groups
                continue;
            }

            // The group doesn't exist in the destination, we create it
            let mut new_group = other_group.to_owned().clone();
            new_group.groups.clear();
            new_group.entries.clear();
            log.events.push(MergeEvent {
                event_type: MergeEventType::GroupCreated,
                node_uuid: new_group.uuid,
            });

            let new_group_parent_group = self
                .root
                .group_by_uuid_mut(current_group.uuid)
                .ok_or(MergeError::FindGroupError(current_group.uuid))?;

            new_group_parent_group.groups.push(new_group.clone());

            let new_merge_log = self.merge_group(other_group, is_in_deleted_group)?;
            log.append(&new_merge_log);
        }

        Ok(log)
    }

    fn relocate_entry(
        &mut self,
        entry_uuid: Uuid,
        from_parent: Uuid,
        to_parent: Uuid,
        new_location_changed_timestamp: NaiveDateTime,
    ) -> Result<(), MergeError> {
        let from_parent = self
            .root
            .group_by_uuid_mut(from_parent)
            .ok_or(MergeError::FindGroupError(from_parent))?;

        let mut relocated_entry = from_parent.remove_entry(entry_uuid)?;
        relocated_entry.times.location_changed = Some(new_location_changed_timestamp);

        let to_parent = self
            .root
            .group_by_uuid_mut(to_parent)
            .ok_or(MergeError::FindGroupError(to_parent))?;

        to_parent.entries.push(relocated_entry);

        Ok(())
    }

    fn relocate_group(
        &mut self,
        group_uuid: Uuid,
        from_parent: Uuid,
        to_parent: Uuid,
        new_location_changed_timestamp: NaiveDateTime,
    ) -> Result<(), MergeError> {
        let from_parent = self
            .root
            .group_by_uuid_mut(from_parent)
            .ok_or(MergeError::FindGroupError(from_parent))?;

        let mut relocated_group = from_parent.remove_group(group_uuid)?;
        relocated_group.times.location_changed = Some(new_location_changed_timestamp);

        let to_parent = self
            .root
            .group_by_uuid_mut(to_parent)
            .ok_or(MergeError::FindGroupError(to_parent))?;

        to_parent.groups.push(relocated_group);
        Ok(())
    }
}

impl Group {
    pub(crate) fn remove_entry(&mut self, uuid: Uuid) -> Result<Entry, MergeError> {
        for i in 0..self.entries.len() {
            if self.entries[i].uuid == uuid {
                return Ok(self.entries.remove(i));
            }
        }

        Err(MergeError::GenericError(format!(
            "Could not find entry {} in group {}.",
            uuid, self.name
        )))
    }

    pub(crate) fn remove_group(&mut self, uuid: Uuid) -> Result<Group, MergeError> {
        for i in 0..self.groups.len() {
            if self.groups[i].uuid == uuid {
                return Ok(self.groups.remove(i));
            }

            if let Ok(removed_group) = self.groups[i].remove_group(uuid) {
                return Ok(removed_group);
            }
        }

        Err(MergeError::GenericError(format!(
            "Could not find group {} in group {}.",
            uuid, self.name
        )))
    }

    pub(crate) fn find_entry_parent(&self, entry_uuid: Uuid) -> Option<Uuid> {
        for entry in &self.entries {
            if entry.uuid == entry_uuid {
                return Some(self.uuid);
            }
        }

        for group in &self.groups {
            if let Some(parent) = group.find_entry_parent(entry_uuid) {
                return Some(parent);
            }
        }

        None
    }

    pub(crate) fn find_group_parent(&self, group_uuid: Uuid) -> Option<Uuid> {
        for group in &self.groups {
            if group.uuid == group_uuid {
                return Some(self.uuid);
            }

            if let Some(parent) = group.find_group_parent(group_uuid) {
                return Some(parent);
            }
        }

        None
    }

    pub(crate) fn merge_with(&mut self, other: &Group) -> Result<MergeLog, MergeError> {
        let mut log = MergeLog::default();

        let source_last_modification = match other.times.last_modification {
            Some(t) => t,
            None => {
                log.warnings.push(format!(
                    "Group {} did not have a last modification timestamp",
                    self.uuid
                ));
                Times::epoch()
            }
        };
        let destination_last_modification = match self.times.last_modification {
            Some(t) => t,
            None => {
                log.warnings.push(format!(
                    "Group {} did not have a last modification timestamp",
                    self.uuid
                ));
                Times::now()
            }
        };

        if destination_last_modification == source_last_modification {
            if self.has_diverged_from(other) {
                // Same timestamp but groups have diverged -- self (destination) wins.
                log.warnings.push(format!(
 "Group {} has same modification time on both sides but content has diverged. Destination version wins.",
 other.uuid
 ));
            }
            // Whether identical or diverged with self-wins, no field update needed.
            return Ok(log);
        }

        if destination_last_modification > source_last_modification {
            return Ok(log);
        }

        self.name = other.name.clone();
        self.notes = other.notes.clone();
        self.icon_id = other.icon_id;
        self.custom_icon_uuid = other.custom_icon_uuid;
        self.custom_icon_data = other.custom_icon_data.clone();
        self.custom_data = other.custom_data.clone();
        self.tags = other.tags.clone();
        self.previous_parent_group = other.previous_parent_group;
        self.unknown_xml = other.unknown_xml.clone();

        // The location changed timestamp is handled separately when merging two databases.
        let current_times = self.times.clone();
        self.times = other.times.clone();
        if let Some(t) = current_times.location_changed {
            self.times.location_changed = Some(t);
        }

        self.is_expanded = other.is_expanded;
        self.default_autotype_sequence = other.default_autotype_sequence.clone();
        self.enable_autotype = other.enable_autotype.clone();
        self.enable_searching = other.enable_searching.clone();
        self.last_top_visible_entry = other.last_top_visible_entry;

        log.events.push(MergeEvent {
            event_type: MergeEventType::GroupUpdated,
            node_uuid: self.uuid,
        });

        Ok(log)
    }

    pub(crate) fn has_diverged_from(&self, other: &Group) -> bool {
        let new_times = Times::new();
        let mut self_purged = self.clone();
        self_purged.times = new_times.clone();
        self_purged.groups.clear();
        self_purged.entries.clear();

        let mut other_purged = other.clone();
        other_purged.times = new_times.clone();
        other_purged.groups.clear();
        other_purged.entries.clear();
        !self_purged.eq(&other_purged)
    }
}

impl Entry {
    pub(crate) fn merge(&self, other: &Entry) -> Result<(Option<Entry>, MergeLog), MergeError> {
        let mut log = MergeLog::default();

        let source_last_modification = match other.times.last_modification {
            Some(t) => t,
            None => {
                log.warnings.push(format!(
                    "Entry {} did not have a last modification timestamp",
                    other.uuid
                ));
                Times::epoch()
            }
        };
        let destination_last_modification = match self.times.last_modification {
            Some(t) => t,
            None => {
                log.warnings.push(format!(
                    "Entry {} did not have a last modification timestamp",
                    self.uuid
                ));
                Times::now()
            }
        };

        if destination_last_modification == source_last_modification {
            if self.has_diverged_from(other) {
                // Same timestamp but entries have diverged -- self (destination) wins.
                // Store the losing version (other) in the winner's history.
                log.warnings.push(format!(
 "Entry {} has same modification time on both sides but content has diverged. Destination version wins.",
 other.uuid
 ));
                let (mut merged_entry, _history_log) = self.merge_history(other)?;
                // Preserve location_changed from self
                if let Some(location_changed_timestamp) = self.times.location_changed {
                    merged_entry.times.location_changed = Some(location_changed_timestamp);
                }
                return Ok((Some(merged_entry), log));
            }
            // Same timestamp and identical content -- no merge needed (no-op)
            return Ok((None, log));
        }

        let (mut merged_entry, entry_merge_log) = match destination_last_modification > source_last_modification
        {
            true => self.merge_history(other)?,
            false => other.clone().merge_history(self)?,
        };

        // The location changed timestamp is handled separately when merging two databases.
        if let Some(location_changed_timestamp) = self.times.location_changed {
            merged_entry.times.location_changed = Some(location_changed_timestamp);
        }

        Ok((Some(merged_entry), entry_merge_log))
    }

    pub(crate) fn merge_history(&self, other: &Entry) -> Result<(Entry, MergeLog), MergeError> {
        let mut log = MergeLog::default();

        let mut source_history = match &other.history {
            Some(h) => h.clone(),
            None => {
                log.warnings.push(format!(
                    "Entry {} from source database had no history.",
                    self.uuid
                ));
                History::default()
            }
        };
        let mut destination_history = match &self.history {
            Some(h) => h.clone(),
            None => {
                log.warnings.push(format!(
                    "Entry {} from destination database had no history.",
                    self.uuid
                ));
                History::default()
            }
        };
        let mut response = self.clone();

        // `self` is whichever side of the merge is authoritative for this
        // entry (see the caller, `Entry::merge`): its live field values
        // become `response`. If it has changes that were never committed to
        // its own history, that snapshot would otherwise be lost once its
        // history is replaced by the merged one below, so stash it just
        // like we already do for `other`. Unlike `other`'s stash (which
        // lands in `source_history` and is merely warned about on a
        // timestamp collision), a collision on this side would land twice
        // in `destination_history` and hard-error in `merge_with` below, so
        // the snapshot is committed with a timestamp guaranteed to be
        // strictly newer than the existing top of history, rather than
        // reusing `response`'s stale `last_modification` (which is prone to
        // colliding with it) or the current wall-clock time alone (which,
        // at KDBX's one-second resolution, could still collide if the last
        // real commit happened within the same second).
        if self.has_uncommitted_changes() {
            log.warnings.push(format!(
                "Entry {} from destination database has uncommitted changes.",
                self.uuid
            ));
            let previous_latest = destination_history.entries.first().and_then(|e| e.times.last_modification);
            let mut commit_time = Times::now();
            if let Some(previous_latest) = previous_latest {
                if commit_time <= previous_latest {
                    commit_time = previous_latest + chrono::Duration::seconds(1);
                }
            }
            let mut committed_snapshot = response.clone();
            committed_snapshot.times.last_modification = Some(commit_time);
            response.times.last_modification = Some(commit_time);
            destination_history.add_entry(committed_snapshot);
        }

        if other.has_uncommitted_changes() {
            log.warnings.push(format!(
                "Entry {} from source database has uncommitted changes.",
                self.uuid
            ));
            source_history.add_entry(other.clone());
        }

        let history_merge_log = destination_history.merge_with(&source_history)?;
        response.history = Some(destination_history);

        Ok((response, log.merge_with(&history_merge_log)))
    }

    // Convenience function used in unit tests, to make sure that:
    // 1. The history gets updated after changing a field
    // 2. We wait a second before committing the changes so that the timestamp is not the same
    // as it previously was. This is necessary since the timestamps in the KDBX format
    // do not preserve the msecs.
    #[cfg(test)]
    pub(crate) fn set_field_and_commit(&mut self, field_name: &str, field_value: &str) {
        self.set_unprotected(field_name, field_value);

        std::thread::sleep(std::time::Duration::from_secs(1));
        self.update_history();
    }

    // Convenience function used in when merging two entries
    pub(crate) fn has_diverged_from(&self, other_entry: &Entry) -> bool {
        let new_times = Times::default();

        let mut self_without_times = self.clone();
        self_without_times.times = new_times.clone();

        let mut other_without_times = other_entry.clone();
        other_without_times.times = new_times.clone();

        !self_without_times.eq(&other_without_times)
    }
}

impl History {
    // Determines if the entries of the history are
    // ordered by last modification time.
    #[cfg(test)]
    pub(crate) fn is_ordered(&self) -> bool {
        let mut last_modification_time: Option<chrono::NaiveDateTime> = None;
        for entry in &self.entries {
            if last_modification_time.is_none() {
                last_modification_time = entry.times.last_modification;
            }

            let entry_modification_time = entry.times.last_modification.unwrap();
            // Equal consecutive timestamps are intentionally treated as
            // still ordered (this checks for a non-increasing/descending
            // sequence, not a strictly decreasing one): KDBX timestamps are
            // second-precision, so two edits within the same second are
            // indistinguishable and legitimately share a modification time.
            if last_modification_time.unwrap() < entry_modification_time {
                return false;
            }
            last_modification_time = Some(entry_modification_time);
        }
        true
    }

    // Merge both histories together. Same-second timestamps are a normal,
    // foreseeable state (see `is_ordered`'s doc comment) rather than purely
    // adversarial, so a collision on either side (or across sides) is
    // handled the same way: the first entry seen at that timestamp wins,
    // destination entries are seen before source entries, and a mismatch
    // between the kept entry and a dropped one is only logged as a warning
    // instead of aborting the whole merge.
    pub(crate) fn merge_with(&mut self, other: &History) -> Result<MergeLog, MergeError> {
        let mut log = MergeLog::default();
        let mut new_history_entries: HashMap<chrono::NaiveDateTime, Entry> = HashMap::new();

        let destination_entries = self.entries.iter().map(|entry| ("Destination", entry));
        let source_entries = other.entries.iter().map(|entry| ("Source", entry));

        for (side, history_entry) in destination_entries.chain(source_entries) {
            let modification_time = history_entry.times.last_modification.unwrap_or_else(|| {
                log.warnings.push(format!(
                    "{side} history entry {} did not have a last modification timestamp",
                    history_entry.uuid
                ));
                Times::epoch()
            });

            match new_history_entries.get(&modification_time) {
                Some(existing_history_entry) => {
                    if existing_history_entry.has_diverged_from(history_entry) {
                        log.warnings.push(format!(
                            "History entries for {} have the same modification timestamp but were not the same.",
                            history_entry.uuid
                        ));
                    }
                }
                None => {
                    new_history_entries.insert(modification_time, history_entry.clone());
                }
            }
        }

        let mut all_modification_times: Vec<&chrono::NaiveDateTime> = new_history_entries.keys().collect();
        all_modification_times.sort();
        all_modification_times.reverse();
        let mut new_entries: Vec<Entry> = vec![];
        for modification_time in &all_modification_times {
            new_entries.push(new_history_entries.get(modification_time).unwrap().clone());
        }

        self.entries = new_entries;
        Ok(log)
    }
}

#[cfg(test)]
mod merge_tests {
    use std::{thread, time};
    use uuid::{uuid, Uuid};

    use crate::db::{fields, Entry, Group, History, Times};
    use crate::db::merge::MergeError;
    use crate::Database;

    fn get_all_groups(parent: &Group) -> Vec<&Group> {
        let mut response: Vec<&Group> = vec![];
        for child_group in &parent.groups {
            response.extend(get_all_groups(child_group));
            response.push(child_group);
        }
        response
    }

    fn get_all_entries(parent: &Group) -> Vec<&Entry> {
        let mut response: Vec<&Entry> = vec![];
        response.extend(parent.entries.iter());

        for child_group in &parent.groups {
            response.extend(get_all_entries(child_group));
        }

        response
    }

    const ROOT_GROUP_ID: Uuid = uuid!("00000000-0000-0000-0000-000000000001");
    const GROUP1_ID: Uuid = uuid!("00000000-0000-0000-0000-000000000002");
    const GROUP2_ID: Uuid = uuid!("00000000-0000-0000-0000-000000000003");
    const SUBGROUP1_ID: Uuid = uuid!("00000000-0000-0000-0000-000000000004");
    const SUBGROUP2_ID: Uuid = uuid!("00000000-0000-0000-0000-000000000005");

    const ENTRY1_ID: Uuid = uuid!("00000000-0000-0000-0000-000000000006");
    const ENTRY2_ID: Uuid = uuid!("00000000-0000-0000-0000-000000000007");

    /// Creates a test database with the following structure:
    /// - root
    /// - entry1
    /// - group1
    /// - subgroup1
    /// - entry2
    ///
    /// - group2
    /// - subgroup2
    fn create_test_database() -> Database {
        let mut db = Database::new(Default::default());
        let mut root_group = Group::new("root");
        root_group.uuid = ROOT_GROUP_ID;

        let mut group1 = Group::new("group1");
        group1.uuid = GROUP1_ID;
        let mut group2 = Group::new("group2");
        group2.uuid = GROUP2_ID;

        let mut subgroup1 = Group::new("subgroup1");
        subgroup1.uuid = SUBGROUP1_ID;
        let mut subgroup2 = Group::new("subgroup2");
        subgroup2.uuid = SUBGROUP2_ID;

        // Placing the first entry in the root group
        let mut entry1 = Entry::new();
        entry1.uuid = ENTRY1_ID;
        entry1.set_field_and_commit(fields::TITLE, "entry1");
        root_group.entries.push(entry1);

        // Placing the second entry in a subgroup
        let mut entry2 = Entry::new();
        entry2.uuid = ENTRY2_ID;
        entry2.set_field_and_commit(fields::TITLE, "entry2");
        subgroup1.entries.push(entry2);

        group1.groups.push(subgroup1);
        group2.groups.push(subgroup2);

        root_group.groups.push(group1);
        root_group.groups.push(group2);

        db.root = root_group;
        db
    }

    #[test]
    fn test_idempotence() {
        let mut destination_db = create_test_database();
        let source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);
        assert_eq!(destination_db.root.groups.len(), 2);
        assert_eq!(destination_db.root.entries.len(), 1);

        // The 2 groups should be exactly the same after merging, since
        // nothing was performed during the merge.
        assert_eq!(destination_db, source_db);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let entry = &mut destination_db.root.entries[0];
        entry.set_field_and_commit(fields::TITLE, "entry1_updated");

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);
        let destination_db_just_after_merge = destination_db.clone();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);
        // Merging twice in a row, even if the first merge updated the destination group,
        // should not create more changes.
        assert_eq!(destination_db_just_after_merge, destination_db);
    }

    #[test]
    fn test_add_new_entry() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let mut new_entry = Entry::new();
        new_entry.set_field_and_commit(fields::TITLE, "new_entry");
        source_db.root.entries.push(new_entry);

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before + 1);
        assert_eq!(group_count_after, group_count_before);

        assert_eq!(destination_db.root.entries.len(), 2);

        let new_entry = destination_db.root.entry_by_name("new_entry").unwrap();
        assert_eq!(new_entry.get_title().unwrap(), "new_entry".to_string());

        // Merging the same group again should not create a duplicate entry.
        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before + 1);
        assert_eq!(group_count_after, group_count_before);
    }

    #[test]
    fn test_deleted_entry_in_destination() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let mut deleted_entry = Entry::new();
        let deleted_entry_uuid = deleted_entry.uuid;
        deleted_entry.set_field_and_commit(fields::TITLE, "deleted_entry");
        source_db.root.entries.push(deleted_entry);

        destination_db
            .deleted_objects
            .insert(deleted_entry_uuid, Some(Times::now()));

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let new_entry = destination_db.root.entry_by_uuid(deleted_entry_uuid);
        assert!(new_entry.is_none());
    }

    #[test]
    fn test_updated_entry_under_deleted_group() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let mut modified_entry = Entry::new();
        modified_entry.set_field_and_commit(fields::TITLE, "original_title");
        destination_db.root.entries.push(modified_entry.clone());

        let mut deleted_group = Group::new("deleted_group");
        let deleted_group_uuid = deleted_group.uuid;
        let modified_entry_uuid = modified_entry.uuid;
        modified_entry.set_field_and_commit(fields::TITLE, "modified_title");
        deleted_group.entries.push(modified_entry);
        source_db.root.groups.push(deleted_group);

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        destination_db
            .deleted_objects
            .insert(deleted_group_uuid, Some(Times::now()));

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let deleted_group = destination_db.root.group_by_uuid(deleted_group_uuid);
        assert!(deleted_group.is_none());

        let modified_entry_location = destination_db.root.entry_by_uuid(modified_entry_uuid);
        assert!(modified_entry_location.is_some());

        let modified_entry = destination_db.root.entry_by_uuid(modified_entry_uuid).unwrap();
        assert_eq!(modified_entry.get_title(), Some("modified_title"));
    }

    #[test]
    fn test_deleted_group_in_destination() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let deleted_group = Group::new("deleted_group");
        let deleted_group_uuid = deleted_group.uuid;
        source_db.root.groups.push(deleted_group);

        destination_db
            .deleted_objects
            .insert(deleted_group_uuid, Some(Times::now()));

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let deleted_group = destination_db.root.group_by_uuid(deleted_group_uuid);
        assert!(deleted_group.is_none());
    }

    #[test]
    fn test_deleted_entry_in_source() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let mut deleted_entry = Entry::new();
        let deleted_entry_uuid = deleted_entry.uuid;
        deleted_entry.set_field_and_commit(fields::TITLE, "deleted_entry");
        destination_db.root.entries.push(deleted_entry);

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        thread::sleep(time::Duration::from_secs(1));
        source_db
            .deleted_objects
            .insert(deleted_entry_uuid, Some(Times::now()));

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before - 1);
        assert_eq!(group_count_after, group_count_before);

        let new_entry = destination_db.root.entry_by_uuid(deleted_entry_uuid);
        assert!(new_entry.is_none());

        assert!(destination_db.deleted_objects.contains_key(&deleted_entry_uuid));
    }

    #[test]
    fn test_deleted_group_in_source() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let deleted_group = Group::new("deleted_group");
        let deleted_group_uuid = deleted_group.uuid;
        destination_db.root.groups.push(deleted_group);

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        thread::sleep(time::Duration::from_secs(1));
        source_db
            .deleted_objects
            .insert(deleted_group_uuid, Some(Times::now()));

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before - 1);

        let deleted_group = destination_db.root.group_by_uuid(deleted_group_uuid);
        assert!(deleted_group.is_none());

        assert!(destination_db.deleted_objects.contains_key(&deleted_group_uuid));
    }

    #[test]
    fn test_deleted_entry_in_source_modified_in_destination() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let deleted_entry_uuid = Uuid::new_v4();

        thread::sleep(time::Duration::from_secs(1));
        source_db
            .deleted_objects
            .insert(deleted_entry_uuid, Some(Times::now()));

        thread::sleep(time::Duration::from_secs(1));
        let mut deleted_entry = Entry::new();
        deleted_entry.uuid = deleted_entry_uuid;
        deleted_entry.set_field_and_commit(fields::TITLE, "deleted_entry");
        destination_db.root.entries.push(deleted_entry);

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let new_entry = destination_db.root.entry_by_uuid(deleted_entry_uuid);
        assert!(new_entry.is_some());

        assert!(!destination_db.deleted_objects.contains_key(&deleted_entry_uuid));
    }

    #[test]
    fn test_group_subtree_deletion() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let deleted_entry_uuid = Uuid::new_v4();
        let deleted_group_uuid = Uuid::new_v4();
        let deleted_subgroup_uuid = Uuid::new_v4();

        thread::sleep(time::Duration::from_secs(1));
        let mut deleted_entry = Entry::new();
        deleted_entry.uuid = deleted_entry_uuid;
        deleted_entry.set_field_and_commit(fields::TITLE, "deleted_entry");

        let mut deleted_subgroup = Group::new("deleted_subgroup");
        deleted_subgroup.uuid = deleted_subgroup_uuid;
        deleted_subgroup.entries.push(deleted_entry);

        let mut deleted_group = Group::new("deleted_group");
        deleted_group.uuid = deleted_group_uuid;
        deleted_group.groups.push(deleted_subgroup);

        destination_db.root.groups.push(deleted_group);

        thread::sleep(time::Duration::from_secs(1));
        source_db
            .deleted_objects
            .insert(deleted_entry_uuid, Some(Times::now()));
        source_db
            .deleted_objects
            .insert(deleted_subgroup_uuid, Some(Times::now()));
        source_db
            .deleted_objects
            .insert(deleted_group_uuid, Some(Times::now()));

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 3);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before - 1);
        assert_eq!(group_count_after, group_count_before - 2);

        let deleted_entry = destination_db.root.entry_by_uuid(deleted_entry_uuid);
        assert!(deleted_entry.is_none());
        let deleted_subgroup = destination_db.root.group_by_uuid(deleted_subgroup_uuid);
        assert!(deleted_subgroup.is_none());
        let deleted_group = destination_db.root.group_by_uuid(deleted_group_uuid);
        assert!(deleted_group.is_none());

        assert!(destination_db.deleted_objects.contains_key(&deleted_entry_uuid));
        assert!(destination_db
            .deleted_objects
            .contains_key(&deleted_subgroup_uuid));
        assert!(destination_db.deleted_objects.contains_key(&deleted_group_uuid));
    }

    #[test]
    fn test_group_subtree_partial_deletion() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let deleted_entry_uuid = Uuid::new_v4();
        let deleted_group_uuid = Uuid::new_v4();
        let deleted_subgroup_uuid = Uuid::new_v4();

        thread::sleep(time::Duration::from_secs(1));
        let mut deleted_entry = Entry::new();
        deleted_entry.uuid = deleted_entry_uuid;
        deleted_entry.set_field_and_commit(fields::TITLE, "deleted_entry");

        let mut deleted_subgroup = Group::new("deleted_subgroup");
        deleted_subgroup.uuid = deleted_subgroup_uuid;
        deleted_subgroup.entries.push(deleted_entry);

        thread::sleep(time::Duration::from_secs(1));
        source_db
            .deleted_objects
            .insert(deleted_entry_uuid, Some(Times::now()));
        source_db
            .deleted_objects
            .insert(deleted_subgroup_uuid, Some(Times::now()));
        source_db
            .deleted_objects
            .insert(deleted_group_uuid, Some(Times::now()));

        thread::sleep(time::Duration::from_secs(1));
        let mut deleted_group = Group::new("deleted_group");
        deleted_group.uuid = deleted_group_uuid;
        deleted_group.groups.push(deleted_subgroup);

        destination_db.root.groups.push(deleted_group);

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 2);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before - 1);
        assert_eq!(group_count_after, group_count_before - 1);

        let deleted_entry = destination_db.root.entry_by_uuid(deleted_entry_uuid);
        assert!(deleted_entry.is_none());
        let deleted_subgroup = destination_db.root.group_by_uuid(deleted_subgroup_uuid);
        assert!(deleted_subgroup.is_none());
        let deleted_group = destination_db.root.group_by_uuid(deleted_group_uuid);
        assert!(deleted_group.is_some());

        assert!(destination_db.deleted_objects.contains_key(&deleted_entry_uuid));
        assert!(destination_db
            .deleted_objects
            .contains_key(&deleted_subgroup_uuid));
        assert!(!destination_db.deleted_objects.contains_key(&deleted_group_uuid));
    }

    #[test]
    fn test_deleted_group_in_source_modified_in_destination() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let deleted_group_uuid = Uuid::new_v4();

        thread::sleep(time::Duration::from_secs(1));
        source_db
            .deleted_objects
            .insert(deleted_group_uuid, Some(Times::now()));

        thread::sleep(time::Duration::from_secs(1));
        let mut deleted_group = Group::new("deleted_group");
        deleted_group.uuid = deleted_group_uuid;
        destination_db.root.groups.push(deleted_group);

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let deleted_group = destination_db.root.group_by_uuid(deleted_group_uuid);
        assert!(deleted_group.is_some());

        assert!(!destination_db.deleted_objects.contains_key(&deleted_group_uuid));
    }

    #[test]
    fn test_deleted_group_has_new_entries() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let mut deleted_group = Group::new("deleted_group");
        let deleted_group_uuid = deleted_group.uuid;

        let mut new_entry = Entry::new();
        let new_entry_uuid = new_entry.uuid;
        new_entry.set_field_and_commit(fields::TITLE, "new_entry");
        deleted_group.entries.push(new_entry);
        destination_db.root.groups.push(deleted_group);

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        thread::sleep(time::Duration::from_secs(1));
        source_db
            .deleted_objects
            .insert(deleted_group_uuid, Some(Times::now()));

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let deleted_group = destination_db.root.group_by_uuid(deleted_group_uuid);
        assert!(deleted_group.is_some());
        let new_entry = destination_db.root.entry_by_uuid(new_entry_uuid);
        assert!(new_entry.is_some());

        assert!(!destination_db.deleted_objects.contains_key(&deleted_group_uuid));
        assert!(!destination_db.deleted_objects.contains_key(&new_entry_uuid));
    }

    #[test]
    fn test_add_new_non_root_entry() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let source_sub_group = &mut source_db.root.groups[0];
        let source_sub_group_uuid = source_sub_group.uuid;

        let mut new_entry = Entry::new();
        let new_entry_uuid = new_entry.uuid;
        new_entry.set_field_and_commit(fields::TITLE, "new_entry");
        source_sub_group.entries.push(new_entry);

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before + 1);
        assert_eq!(group_count_after, group_count_before);

        let created_entry_parent = destination_db.root.find_entry_parent(new_entry_uuid).unwrap();
        assert_eq!(created_entry_parent, source_sub_group_uuid);
    }

    #[test]
    fn test_add_new_entry_new_group() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let group_count_before = get_all_groups(&destination_db.root).len();
        let entry_count_before = get_all_entries(&destination_db.root).len();

        let mut source_group = Group::new("new_group");
        let mut source_sub_group = Group::new("new_subgroup");

        let mut new_entry = Entry::new();
        let new_entry_uuid = new_entry.uuid;
        new_entry.set_field_and_commit(fields::TITLE, "new_entry");
        source_sub_group.entries.push(new_entry);
        source_group.groups.push(source_sub_group.clone());
        source_db.root.groups.push(source_group);

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 3);

        let group_count_after = get_all_groups(&destination_db.root).len();
        let entry_count_after = get_all_entries(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before + 1);
        assert_eq!(group_count_after, group_count_before + 2);

        let created_entry_parent = destination_db.root.find_entry_parent(new_entry_uuid).unwrap();
        assert_eq!(created_entry_parent, source_sub_group.uuid);
    }

    #[test]
    fn test_entry_relocation_existing_group() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let group_count_before = get_all_groups(&destination_db.root).len();
        let entry_count_before = get_all_entries(&destination_db.root).len();

        thread::sleep(time::Duration::from_secs(1));
        let new_location_changed_timestamp = Times::now();

        source_db
            .relocate_entry(ENTRY2_ID, SUBGROUP1_ID, GROUP2_ID, new_location_changed_timestamp)
            .unwrap();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let group_count_after = get_all_groups(&destination_db.root).len();
        let entry_count_after = get_all_entries(&destination_db.root).len();
        assert_eq!(group_count_after, group_count_before);
        assert_eq!(entry_count_after, entry_count_before);

        let moved_entry_parent = destination_db.root.find_entry_parent(ENTRY2_ID).unwrap();
        assert_eq!(moved_entry_parent, GROUP2_ID);

        let moved_entry = destination_db
            .root
            .group_by_name("group2")
            .and_then(|g| g.entry_by_name("entry2"))
            .unwrap();

        assert_eq!(
            moved_entry.times.location_changed.unwrap(),
            new_location_changed_timestamp
        );
    }

    #[test]
    fn test_entry_relocation_and_update() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let group_count_before = get_all_groups(&destination_db.root).len();
        let entry_count_before = get_all_entries(&destination_db.root).len();

        let entry2 = source_db.root.entry_by_uuid_mut(ENTRY2_ID).unwrap();
        entry2.set_field_and_commit(fields::TITLE, "entry2_modified_in_source");

        thread::sleep(time::Duration::from_secs(1));
        let new_location_changed_timestamp = Times::now();
        source_db
            .relocate_entry(ENTRY2_ID, SUBGROUP1_ID, GROUP2_ID, new_location_changed_timestamp)
            .unwrap();

        let entry2 = destination_db.root.entry_by_uuid_mut(ENTRY2_ID).unwrap();
        entry2.set_field_and_commit(fields::TITLE, "entry2_modified_in_destination");
        let entry_modified_timestamp = entry2.times.last_modification.unwrap();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 2);

        let group_count_after = get_all_groups(&destination_db.root).len();
        let entry_count_after = get_all_entries(&destination_db.root).len();
        assert_eq!(group_count_after, group_count_before);
        assert_eq!(entry_count_after, entry_count_before);

        let moved_entry_parent = destination_db.root.find_entry_parent(ENTRY2_ID).unwrap();
        assert_eq!(moved_entry_parent, GROUP2_ID);

        let moved_entry = destination_db
            .root
            .group_by_name("group2")
            .and_then(|g| g.entry_by_name("entry2_modified_in_destination"))
            .unwrap();

        assert_eq!(
            moved_entry.times.last_modification.unwrap(),
            entry_modified_timestamp,
        );
        assert_eq!(
            moved_entry.times.location_changed.unwrap(),
            new_location_changed_timestamp
        );
    }

    #[test]
    fn test_entry_relocation_in_destination_and_update() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let group_count_before = get_all_groups(&destination_db.root).len();
        let entry_count_before = get_all_entries(&destination_db.root).len();

        let entry2 = source_db.root.entry_by_uuid_mut(ENTRY2_ID).unwrap();
        entry2.set_field_and_commit(fields::TITLE, "entry2_modified_in_source");

        let entry_modified_timestamp = entry2.times.last_modification.unwrap();

        thread::sleep(time::Duration::from_secs(1));
        let new_location_changed_timestamp = Times::now();
        destination_db
            .relocate_entry(ENTRY2_ID, SUBGROUP1_ID, GROUP2_ID, new_location_changed_timestamp)
            .unwrap();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let group_count_after = get_all_groups(&destination_db.root).len();
        let entry_count_after = get_all_entries(&destination_db.root).len();
        assert_eq!(group_count_after, group_count_before);
        assert_eq!(entry_count_after, entry_count_before);

        let moved_entry_parent = destination_db.root.find_entry_parent(ENTRY2_ID).unwrap();
        assert_eq!(moved_entry_parent, GROUP2_ID);

        let moved_entry = destination_db
            .root
            .group_by_name("group2")
            .and_then(|g| g.entry_by_name("entry2_modified_in_source"))
            .unwrap();

        assert_eq!(
            moved_entry.times.last_modification.unwrap(),
            entry_modified_timestamp,
        );
        assert_eq!(
            moved_entry.times.location_changed.unwrap(),
            new_location_changed_timestamp
        );
    }

    #[test]
    fn test_entry_relocation_new_group() {
        let mut destination_db = create_test_database();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let mut source_db = destination_db.clone();
        let mut new_group = Group::new("new_group");
        let new_group_uuid = new_group.uuid;

        let mut new_entry = Entry::new();
        let entry_uuid = new_entry.uuid;
        new_entry.set_field_and_commit(fields::TITLE, "entry1");

        thread::sleep(time::Duration::from_secs(1));
        new_entry.times.location_changed = Some(Times::now());
        // update_history() here would be a no-op: has_uncommitted_changes()
        // ignores `times` when comparing against the last commit made just
        // above via set_field_and_commit, and only `times.location_changed`
        // changed since then.
        new_group.entries.push(new_entry.clone());
        source_db.root.groups.push(new_group);

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 2);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before + 1);
        assert_eq!(group_count_after, group_count_before + 1);

        let created_entry_parent = destination_db.root.find_entry_parent(entry_uuid).unwrap();
        assert_eq!(created_entry_parent, new_group_uuid);
    }

    #[test]
    fn test_group_relocation() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let source_group_1 = source_db.root.group_by_name_mut("group1").unwrap();
        let mut source_sub_group_1 = source_group_1.remove_group(SUBGROUP1_ID).unwrap();

        thread::sleep(time::Duration::from_secs(1));
        let new_location_changed_timestamp = Times::now();
        source_sub_group_1.times.location_changed = Some(new_location_changed_timestamp);

        let source_group_2 = source_db.root.group_by_name_mut("group2").unwrap();
        source_group_2.groups.push(source_sub_group_1);

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let created_entry_parent = destination_db.root.find_entry_parent(ENTRY2_ID).unwrap();
        assert_eq!(created_entry_parent, SUBGROUP1_ID);

        let relocated_group = destination_db
            .root
            .group_by_path(&["group2", "subgroup1"])
            .unwrap();

        assert_eq!(
            relocated_group.times.location_changed.unwrap(),
            new_location_changed_timestamp
        );
    }

    #[test]
    fn test_update_in_destination_no_conflict() {
        let mut destination_db = create_test_database();
        let source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let entry = &mut destination_db.root.entries[0];
        entry.set_field_and_commit(fields::TITLE, "entry1_updated");

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);

        let entry = &mut destination_db.root.entries[0];
        let merged_history = entry.history.clone().unwrap();
        assert!(merged_history.is_ordered());
        assert_eq!(merged_history.entries.len(), 2);
        let merged_entry = &merged_history.entries[1];
        assert_eq!(merged_entry.get_title(), Some("entry1"));

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let entry = &destination_db.root.entries[0];
        assert_eq!(entry.get_title(), Some("entry1_updated"));
    }

    #[test]
    fn test_update_in_source_no_conflict() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let entry = &mut source_db.root.entries[0];
        entry.set_field_and_commit(fields::TITLE, "entry1_updated");

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry = &mut destination_db.root.entries[0];
        let merged_history = entry.history.clone().unwrap();
        assert!(merged_history.is_ordered());
        assert_eq!(merged_history.entries.len(), 2);
        let merged_entry = &merged_history.entries[1];
        assert_eq!(merged_entry.get_title(), Some("entry1"));

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let entry = &destination_db.root.entries[0];
        assert_eq!(entry.get_title(), Some("entry1_updated"));
    }

    #[test]
    fn test_update_with_conflicts() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let entry = &mut destination_db.root.entries[0];
        entry.set_field_and_commit(fields::TITLE, "entry1_updated_from_destination");

        let entry = &mut source_db.root.entries[0];
        entry.set_field_and_commit(fields::TITLE, "entry1_updated_from_source");

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let entry = &destination_db.root.entries[0];
        assert_eq!(entry.get_title(), Some("entry1_updated_from_source"));

        let merged_history = entry.history.clone().unwrap();
        assert!(merged_history.is_ordered());
        assert_eq!(merged_history.entries.len(), 3);
        let merged_entry = &merged_history.entries[1];
        assert_eq!(merged_entry.get_title(), Some("entry1_updated_from_destination"));

        // Merging again should not result in any additional change.
        let merge_result = destination_db.merge(&destination_db.clone()).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);
    }

    #[test]
    fn test_group_update_in_source() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let group = source_db
            .root
            .group_by_path_mut(&["group1", "subgroup1"])
            .unwrap();
        group.name = "subgroup1_updated_name".to_string();

        // Making sure to wait 1 sec before update the timestamp, to make
        // sure that we get a different modification timestamp.
        thread::sleep(time::Duration::from_secs(1));
        let new_modification_timestamp = Times::now();
        group.times.last_modification = Some(new_modification_timestamp);

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let modified_group = destination_db
            .root
            .group_by_path(&["group1", "subgroup1_updated_name"])
            .unwrap();

        assert_eq!(modified_group.name, "subgroup1_updated_name");
        assert_eq!(
            modified_group.times.last_modification,
            Some(new_modification_timestamp),
        );
    }

    #[test]
    fn test_group_update_in_source_carries_over_tags_previous_parent_and_unknown_xml() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let group = source_db
            .root
            .group_by_path_mut(&["group1", "subgroup1"])
            .unwrap();
        group.tags = Some("work;personal".to_string());
        group.previous_parent_group = Some(Uuid::new_v4());
        group.unknown_xml = vec![crate::format::xml_db::xml_node::XmlNode {
            name: "AnUnknownGroupField".to_string(),
            inner_xml: "some-value".to_string(),
        }];

        // Making sure to wait 1 sec before updating the timestamp, to make
        // sure that we get a different modification timestamp.
        thread::sleep(time::Duration::from_secs(1));
        group.times.last_modification = Some(Times::now());

        let expected_tags = group.tags.clone();
        let expected_previous_parent_group = group.previous_parent_group;
        let expected_unknown_xml = group.unknown_xml.clone();

        destination_db.merge(&source_db).unwrap();

        let modified_group = destination_db
            .root
            .group_by_path(&["group1", "subgroup1"])
            .unwrap();
        assert_eq!(modified_group.tags, expected_tags);
        assert_eq!(
            modified_group.previous_parent_group,
            expected_previous_parent_group
        );
        assert_eq!(modified_group.unknown_xml, expected_unknown_xml);
    }

    #[test]
    fn test_merge_backfills_group_custom_icon_data_from_source() {
        let mut destination_db = create_test_database();
        let source_db = destination_db.clone();

        let icon_uuid = Uuid::new_v4();
        let icon_data = vec![1, 2, 3, 4];

        // Destination group references a custom icon but is missing its data
        // (e.g. it was assigned locally before the icon bytes synced down).
        let destination_group = destination_db
            .root
            .group_by_path_mut(&["group1", "subgroup1"])
            .unwrap();
        destination_group.custom_icon_uuid = Some(icon_uuid);
        destination_group.custom_icon_data = None;

        // Source database carries the actual icon bytes on an entry.
        let mut source_db = source_db;
        source_db.root.entries[0].custom_icon = Some((icon_uuid, icon_data.clone()));

        destination_db.merge(&source_db).unwrap();

        let modified_group = destination_db
            .root
            .group_by_path(&["group1", "subgroup1"])
            .unwrap();
        assert_eq!(modified_group.custom_icon_uuid, Some(icon_uuid));
        assert_eq!(modified_group.custom_icon_data, Some(icon_data));
    }

    #[test]
    fn test_merge_errors_instead_of_panicking_on_group_uuid_colliding_with_destination_root() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        // Craft a malformed source database where a non-root group shares its
        // UUID with the *destination's* root group. `group_by_uuid` matches
        // the destination root against itself, but `find_group_parent` can
        // never resolve a parent for the root, so this used to unwrap a
        // `None` and panic instead of failing the merge with an error.
        let colliding_uuid = destination_db.root.uuid;
        source_db
            .root
            .group_by_path_mut(&["group1"])
            .unwrap()
            .uuid = colliding_uuid;

        let result = destination_db.merge(&source_db);
        assert!(matches!(result, Err(MergeError::FindGroupError(uuid)) if uuid == colliding_uuid));
    }

    #[test]
    fn test_group_update_in_destination() {
        let mut destination_db = create_test_database();
        let source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let group = destination_db
            .root
            .group_by_path_mut(&["group1", "subgroup1"])
            .unwrap();
        group.name = "subgroup1_updated_name".to_string();
        // Making sure to wait 1 sec before update the timestamp, to make
        // sure that we get a different modification timestamp.
        thread::sleep(time::Duration::from_secs(1));
        let new_modification_timestamp = Times::now();
        group.times.last_modification = Some(new_modification_timestamp);

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 0);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let modified_group = destination_db
            .root
            .group_by_path(&["group1", "subgroup1_updated_name"])
            .unwrap();
        assert_eq!(modified_group.name, "subgroup1_updated_name");
        assert_eq!(
            modified_group.times.last_modification,
            Some(new_modification_timestamp),
        );
    }

    #[test]
    fn test_group_update_and_relocation() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let group = source_db
            .root
            .group_by_path_mut(&["group1", "subgroup1"])
            .unwrap();
        group.name = "subgroup1_updated_name".to_string();
        // Making sure to wait 1 sec before update the timestamp, to make
        // sure that we get a different modification timestamp.
        thread::sleep(time::Duration::from_secs(1));
        let new_modification_timestamp = Times::now();
        group.times.last_modification = Some(new_modification_timestamp);

        source_db
            .relocate_group(SUBGROUP1_ID, GROUP1_ID, GROUP2_ID, new_modification_timestamp)
            .unwrap();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 2);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let modified_group = destination_db
            .root
            .group_by_path(&["group2", "subgroup1_updated_name"])
            .unwrap();
        assert_eq!(modified_group.name, "subgroup1_updated_name");
        assert_eq!(
            modified_group.times.last_modification,
            Some(new_modification_timestamp),
        );
    }

    #[test]
    fn test_group_update_in_destination_and_relocation_in_source() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        let entry_count_before = get_all_entries(&destination_db.root).len();
        let group_count_before = get_all_groups(&destination_db.root).len();

        let group = source_db
            .root
            .group_by_path_mut(&["group1", "subgroup1"])
            .unwrap();
        group.name = "subgroup1_updated_name".to_string();
        // Making sure to wait 1 sec before update the timestamp, to make
        // sure that we get a different modification timestamp.
        thread::sleep(time::Duration::from_secs(1));
        let new_modification_timestamp = Times::now();
        group.times.last_modification = Some(new_modification_timestamp);

        thread::sleep(time::Duration::from_secs(1));
        let new_location_changed_timestamp = Times::now();
        destination_db
            .relocate_group(SUBGROUP1_ID, GROUP1_ID, GROUP2_ID, new_location_changed_timestamp)
            .unwrap();

        let merge_result = destination_db.merge(&source_db).unwrap();
        assert_eq!(merge_result.warnings.len(), 0);
        assert_eq!(merge_result.events.len(), 1);

        let entry_count_after = get_all_entries(&destination_db.root).len();
        let group_count_after = get_all_groups(&destination_db.root).len();
        assert_eq!(entry_count_after, entry_count_before);
        assert_eq!(group_count_after, group_count_before);

        let modified_group = destination_db
            .root
            .group_by_path(&["group2", "subgroup1_updated_name"])
            .unwrap();
        assert_eq!(modified_group.name, "subgroup1_updated_name");
        assert_eq!(
            modified_group.times.last_modification,
            Some(new_modification_timestamp),
        );
        assert_eq!(
            modified_group.times.location_changed,
            Some(new_location_changed_timestamp),
        );
    }

    #[test]
    fn test_history_merge_with_missing_source_timestamp_does_not_panic() {
        let mut other_entry = Entry::new();
        other_entry.uuid = ENTRY1_ID;
        other_entry.times.last_modification = None;
        let other_history = History {
            entries: vec![other_entry],
        };

        let mut destination = History::default();
        let merge_log = destination.merge_with(&other_history).unwrap();
        assert_eq!(merge_log.warnings.len(), 1);
        assert_eq!(destination.entries.len(), 1);
    }

    fn history_entry_at(uuid: Uuid, modification_time: chrono::NaiveDateTime) -> Entry {
        let mut entry = Entry::new();
        entry.uuid = uuid;
        entry.times.last_modification = Some(modification_time);
        entry
    }

    #[test]
    fn test_history_merge_with_duplicate_destination_timestamps_warns_instead_of_erroring() {
        let t = Times::now();
        let mut destination = History {
            entries: vec![history_entry_at(ENTRY1_ID, t), history_entry_at(ENTRY2_ID, t)],
        };

        let merge_log = destination
            .merge_with(&History::default())
            .expect("duplicate same-second timestamps within the destination should not hard-error");

        assert_eq!(merge_log.warnings.len(), 1);
        assert_eq!(destination.entries.len(), 1, "the later duplicate should be dropped");
        assert_eq!(destination.entries[0].uuid, ENTRY1_ID, "the first entry seen should win");
    }

    #[test]
    fn test_history_merge_with_duplicate_source_timestamps_warns_and_dedupes() {
        let t = Times::now();
        let mut destination = History::default();
        let other = History {
            entries: vec![history_entry_at(ENTRY1_ID, t), history_entry_at(ENTRY2_ID, t)],
        };

        let merge_log = destination.merge_with(&other).unwrap();

        assert_eq!(merge_log.warnings.len(), 1);
        assert_eq!(destination.entries.len(), 1, "the later duplicate should be dropped");
        assert_eq!(destination.entries[0].uuid, ENTRY1_ID, "the first entry seen should win");
    }

    #[test]
    fn test_history_merge_with_cross_side_timestamp_collision_keeps_destination_entry() {
        let t = Times::now();
        let mut destination = History {
            entries: vec![history_entry_at(ENTRY1_ID, t)],
        };
        let other = History {
            entries: vec![history_entry_at(ENTRY2_ID, t)],
        };

        let merge_log = destination.merge_with(&other).unwrap();

        assert_eq!(merge_log.warnings.len(), 1);
        assert_eq!(destination.entries.len(), 1);
        assert_eq!(
            destination.entries[0].uuid, ENTRY1_ID,
            "destination entries are seen before source entries, so destination should win"
        );
    }

    #[test]
    fn test_merge_takes_newer_side_for_each_timestamped_meta_field() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        thread::sleep(time::Duration::from_secs(1));
        let later = Times::now();

        // Destination is newer for the database name...
        destination_db.meta.database_name = Some("destination name".to_string());
        destination_db.meta.database_name_changed = Some(later);
        source_db.meta.database_name = Some("source name".to_string());
        source_db.meta.database_name_changed = Some(Times::now() - chrono::Duration::seconds(10));

        // ...but the source is newer for the description.
        source_db.meta.database_description = Some("source description".to_string());
        source_db.meta.database_description_changed = Some(later);
        destination_db.meta.database_description = Some("destination description".to_string());
        destination_db.meta.database_description_changed = Some(Times::now() - chrono::Duration::seconds(10));

        destination_db.merge(&source_db).unwrap();

        assert_eq!(destination_db.meta.database_name, Some("destination name".to_string()));
        assert_eq!(
            destination_db.meta.database_description,
            Some("source description".to_string())
        );
    }

    #[test]
    fn test_merge_takes_settings_changed_side_for_unclaimed_meta_fields() {
        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        destination_db.meta.settings_changed = Some(Times::now() - chrono::Duration::seconds(10));
        destination_db.meta.history_max_items = Some(5);

        thread::sleep(time::Duration::from_secs(1));
        source_db.meta.settings_changed = Some(Times::now());
        source_db.meta.history_max_items = Some(50);

        destination_db.merge(&source_db).unwrap();

        assert_eq!(destination_db.meta.history_max_items, Some(50));
        assert_eq!(destination_db.meta.settings_changed, source_db.meta.settings_changed);
    }

    #[test]
    fn test_merge_unions_meta_custom_data_keeping_newer_item_on_key_collision() {
        use crate::db::CustomDataItem;
        use crate::db::CustomDataValue;

        let mut destination_db = create_test_database();
        let mut source_db = destination_db.clone();

        destination_db.meta.custom_data.insert(
            "only_in_destination".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("dest-only".to_string())),
                last_modification_time: Some(Times::now()),
                unknown_xml: Vec::new(),
            },
        );
        destination_db.meta.custom_data.insert(
            "shared".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("stale".to_string())),
                last_modification_time: Some(Times::now() - chrono::Duration::seconds(10)),
                unknown_xml: Vec::new(),
            },
        );

        thread::sleep(time::Duration::from_secs(1));
        source_db.meta.custom_data.insert(
            "shared".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("fresh".to_string())),
                last_modification_time: Some(Times::now()),
                unknown_xml: Vec::new(),
            },
        );
        source_db.meta.custom_data.insert(
            "only_in_source".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("source-only".to_string())),
                last_modification_time: Some(Times::now()),
                unknown_xml: Vec::new(),
            },
        );

        destination_db.merge(&source_db).unwrap();

        assert_eq!(destination_db.meta.custom_data.len(), 3);
        assert_eq!(
            destination_db.meta.custom_data["shared"].value,
            Some(CustomDataValue::String("fresh".to_string()))
        );
        assert_eq!(
            destination_db.meta.custom_data["only_in_destination"].value,
            Some(CustomDataValue::String("dest-only".to_string()))
        );
        assert_eq!(
            destination_db.meta.custom_data["only_in_source"].value,
            Some(CustomDataValue::String("source-only".to_string()))
        );
    }
}
