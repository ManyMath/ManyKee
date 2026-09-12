//! Comprehensive merge test suite.
//!
//! All fixtures are programmatic -- no external KDBX files needed.
//! Tests use round-trip (save+reopen) to establish proper timestamps.

mod common;

use std::ffi::OsString;
use std::io::Cursor;
use std::path::Path;
use std::thread;
use std::time::Duration;

use common::official_tools::{
    discover_keepassxc, mode_from_env, run_keepassxc_with_stdin_lines, OfficialTool,
    RedactedOutput, REQUIRED_KEEPASSXC_VERSION,
};
use keepass::config::DatabaseConfig;
use keepass::db::{fields, Database, Entry, Group, Times};
use keepass::DatabaseKey;
use keepassxc::merge::{merge, ConflictResolution, MergeWarning};
use keepassxc::EntryExt;
use uuid::Uuid;

const TEST_PASSWORD: &str = "test";

fn make_key() -> DatabaseKey {
    DatabaseKey::new().with_password(TEST_PASSWORD)
}

/// Create a minimal database, save it, and reopen it so all timestamps
/// are properly initialised from the serialisation layer.
fn create_base_db() -> Database {
    let mut db = Database::new(DatabaseConfig::default());
    db.root.name = "Root".to_string();

    let mut entry1 = Entry::new();
    entry1.set_unprotected(fields::TITLE, "Entry One");
    entry1.set_unprotected(fields::USERNAME, "user1");
    db.root.entries.push(entry1);

    let mut entry2 = Entry::new();
    entry2.set_unprotected(fields::TITLE, "Entry Two");
    entry2.set_unprotected(fields::USERNAME, "user2");
    db.root.entries.push(entry2);

    let mut subgroup = Group::new("SubGroup");
    let mut entry3 = Entry::new();
    entry3.set_unprotected(fields::TITLE, "Entry Three");
    subgroup.entries.push(entry3);
    db.root.groups.push(subgroup);

    round_trip(&db)
}

/// Save and reopen a database to establish proper timestamps and structure.
fn round_trip(db: &Database) -> Database {
    let key = make_key();
    let mut buf = Vec::new();
    db.save(&mut buf, key.clone()).expect("save failed");
    Database::open(&mut Cursor::new(&buf), key).expect("open failed")
}

/// Clone a database by serialising and deserialising it.
fn clone_db(db: &Database) -> Database {
    round_trip(db)
}

/// Replicate `Entry::set_field_and_commit` which is pub(crate) in keepass-rs.
/// Sets a field, sleeps 1s for timestamp resolution, then commits to history.
fn set_field_and_commit(entry: &mut Entry, field: &str, value: &str) {
    entry.set_unprotected(field, value);
    thread::sleep(Duration::from_secs(1));
    entry.update_history();
}

/// Count all entries recursively in a group tree.
fn count_entries(group: &Group) -> usize {
    let mut count = group.entries.len();
    for child in &group.groups {
        count += count_entries(child);
    }
    count
}

/// Merge matches by UUID, no duplicates created.
#[test]
fn test_merge_matches_by_uuid() {
    let base = create_base_db();
    let base_entry_count = count_entries(&base.root);

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Add a new entry to source only
    let mut new_entry = Entry::new();
    new_entry.set_unprotected(fields::TITLE, "New Source Entry");
    db_b.root.entries.push(new_entry);

    let result = merge(&mut db_a, &db_b).expect("merge failed");

    // Should have base entries + 1 new entry (no duplicates)
    let merged_count = count_entries(&db_a.root);
    assert_eq!(
        merged_count,
        base_entry_count + 1,
        "Expected {} entries but got {} (UUID matching should prevent duplicates)",
        base_entry_count + 1,
        merged_count
    );
    assert_eq!(result.entries_added, 1);
}

/// Same entry edited on both sides -- newer version wins.
#[test]
fn test_merge_newer_entry_wins() {
    let base = create_base_db();
    let entry1_uuid = base.root.entries[0].uuid;

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Edit entry on db_a first
    let entry_a = db_a.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    set_field_and_commit(entry_a, fields::TITLE, "Edited A");

    // Sleep to ensure different timestamp (KDBX has 1-second resolution)
    thread::sleep(Duration::from_secs(1));

    // Edit same entry on db_b (newer)
    let entry_b = db_b.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    set_field_and_commit(entry_b, fields::TITLE, "Edited B");

    // Merge db_b (source) into db_a (destination)
    let result = merge(&mut db_a, &db_b).expect("merge failed");

    let merged_entry = db_a.root.find_entry_by_uuid(entry1_uuid).unwrap();
    assert_eq!(
        merged_entry.get(fields::TITLE),
        Some("Edited B"),
        "Newer version (Edited B) should win"
    );
    assert!(result.entries_updated >= 1);
}

/// After conflict resolution, losing version appears in winner's history.
#[test]
fn test_merge_loser_stored_in_history() {
    let base = create_base_db();
    let entry1_uuid = base.root.entries[0].uuid;

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Edit on db_a (will be the loser)
    let entry_a = db_a.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    set_field_and_commit(entry_a, fields::TITLE, "Edited A");

    thread::sleep(Duration::from_secs(1));

    // Edit on db_b (will be the winner - newer)
    let entry_b = db_b.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    set_field_and_commit(entry_b, fields::TITLE, "Edited B");

    merge(&mut db_a, &db_b).expect("merge failed");

    let merged_entry = db_a.root.find_entry_by_uuid(entry1_uuid).unwrap();
    let history = merged_entry.history.as_ref().expect("history should exist");
    let history_entries = history.get_entries();

    // The loser ("Edited A") should appear in history
    let has_loser = history_entries
        .iter()
        .any(|e| e.get(fields::TITLE) == Some("Edited A"));
    assert!(
        has_loser,
        "History should contain the losing version 'Edited A'"
    );
}

/// If the winning side of a merge itself has uncommitted changes (field
/// edits made without calling `update_history`), that state must be
/// captured into history rather than silently dropped once the merged
/// history replaces it.
#[test]
fn test_merge_winner_uncommitted_changes_preserved_in_history() {
    let base = create_base_db();
    let entry1_uuid = base.root.entries[0].uuid;

    let mut db_a = clone_db(&base);
    let db_b = clone_db(&base);

    // db_a will be the merge winner: give it a committed edit so its
    // last_modification is newer than db_b's, then make a further,
    // uncommitted edit on top of it.
    let entry_a = db_a.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    set_field_and_commit(entry_a, fields::TITLE, "Committed A");
    entry_a.set_unprotected(fields::USERNAME, "UncommittedA");

    merge(&mut db_a, &db_b).expect("merge failed");

    let merged_entry = db_a.root.find_entry_by_uuid(entry1_uuid).unwrap();

    // The live entry keeps the uncommitted edit.
    assert_eq!(merged_entry.get(fields::USERNAME), Some("UncommittedA"));

    let history = merged_entry.history.as_ref().expect("history should exist");
    let has_uncommitted_snapshot = history.get_entries().iter().any(|e| {
        e.get(fields::TITLE) == Some("Committed A")
            && e.get(fields::USERNAME) == Some("UncommittedA")
    });
    assert!(
        has_uncommitted_snapshot,
        "the winner's uncommitted state should have been captured into history, not dropped"
    );
}

/// Deleted entry (in DeletedObjects) does not reappear after merge.
#[test]
fn test_merge_deleted_entry_stays_deleted() {
    let base = create_base_db();
    let entry2_uuid = base.root.entries[1].uuid;

    let mut db_a = clone_db(&base);
    let db_b = clone_db(&base);

    // Delete entry2 on db_a (hard delete records it in DeletedObjects)
    keepassxc::delete_entry(&mut db_a, entry2_uuid, false).expect("delete failed");

    // Verify entry2 is in deleted_objects
    assert!(db_a.deleted_objects.contains_key(&entry2_uuid));

    // entry2 still exists in db_b -- merge should NOT resurrect it
    merge(&mut db_a, &db_b).expect("merge failed");

    assert!(
        db_a.root.find_entry_by_uuid(entry2_uuid).is_none(),
        "Deleted entry should not reappear after merge (anti-resurrection via DeletedObjects)"
    );
}

/// Group relocation resolved by LocationChanged timestamp.
#[test]
fn test_merge_group_relocation() {
    let base = create_base_db();
    let subgroup_uuid = base.root.groups[0].uuid;

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Create target groups in both databases
    let target_a = Group::new("TargetA");
    let target_a_uuid = target_a.uuid;
    db_a.root.groups.push(target_a);

    // Create the same target group in db_b (with same UUID)
    let target_b = Group::new("TargetB");
    let target_b_uuid = target_b.uuid;
    db_b.root.groups.push(target_b);

    // Also add TargetA and TargetB to both DBs so they exist as merge targets
    let mut target_a_for_b = Group::new("TargetA");
    target_a_for_b.uuid = target_a_uuid;
    db_b.root.groups.push(target_a_for_b);

    let mut target_b_for_a = Group::new("TargetB");
    target_b_for_a.uuid = target_b_uuid;
    db_a.root.groups.push(target_b_for_a);

    // Move SubGroup to TargetA in db_a
    let subgroup_a = db_a
        .root
        .groups
        .iter()
        .position(|g| g.uuid == subgroup_uuid)
        .unwrap();
    let mut moved = db_a.root.groups.remove(subgroup_a);
    moved.times.location_changed = Some(Times::now());
    let target_a_group = db_a
        .root
        .groups
        .iter_mut()
        .find(|g| g.uuid == target_a_uuid)
        .unwrap();
    target_a_group.groups.push(moved);

    thread::sleep(Duration::from_secs(1));

    // Move SubGroup to TargetB in db_b (later timestamp -- should win)
    let subgroup_b = db_b
        .root
        .groups
        .iter()
        .position(|g| g.uuid == subgroup_uuid)
        .unwrap();
    let mut moved_b = db_b.root.groups.remove(subgroup_b);
    moved_b.times.location_changed = Some(Times::now());
    let target_b_group = db_b
        .root
        .groups
        .iter_mut()
        .find(|g| g.uuid == target_b_uuid)
        .unwrap();
    target_b_group.groups.push(moved_b);

    let _result = merge(&mut db_a, &db_b).expect("merge failed");

    // SubGroup should be under TargetB (the one with the newer LocationChanged)
    let target_b_merged = db_a
        .root
        .groups
        .iter()
        .find(|g| g.uuid == target_b_uuid)
        .expect("TargetB should exist");
    let found_in_b = target_b_merged
        .groups
        .iter()
        .any(|g| g.uuid == subgroup_uuid);
    assert!(
        found_in_b,
        "SubGroup should be relocated to TargetB (newer LocationChanged)"
    );
}

/// Custom icons from both databases preserved in merged output.
#[test]
fn test_merge_custom_icons_preserved() {
    let base = create_base_db();
    let entry1_uuid = base.root.entries[0].uuid;

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Add a custom icon to entry1 in db_b
    let icon_uuid = Uuid::new_v4();
    let icon_data: Vec<u8> = vec![0x89, 0x50, 0x4E, 0x47]; // fake PNG header
    let entry_b = db_b.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    entry_b.custom_icon = Some((icon_uuid, icon_data.clone()));
    // Bump modification time so source wins
    thread::sleep(Duration::from_secs(1));
    entry_b.times.last_modification = Some(Times::now());

    merge(&mut db_a, &db_b).expect("merge failed");

    // After merge, entry1 in db_a should have the custom icon
    let merged_entry = db_a.root.find_entry_by_uuid(entry1_uuid).unwrap();
    assert!(
        merged_entry.custom_icon.is_some(),
        "Custom icon should be preserved after merge"
    );
    let (merged_icon_uuid, merged_icon_data) = merged_entry.custom_icon.as_ref().unwrap();
    assert_eq!(*merged_icon_uuid, icon_uuid);
    assert_eq!(*merged_icon_data, icon_data);
}

/// Entry history from both source databases preserved in merged result.
#[test]
fn test_merge_history_union() {
    let base = create_base_db();
    let entry1_uuid = base.root.entries[0].uuid;

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Create a history entry on db_a by editing
    let entry_a = db_a.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    set_field_and_commit(entry_a, fields::USERNAME, "historyA");
    let db_a_history_count = db_a
        .root
        .find_entry_by_uuid(entry1_uuid)
        .unwrap()
        .history
        .as_ref()
        .map_or(0, |h| h.get_entries().len());

    thread::sleep(Duration::from_secs(1));

    // Create a different history entry on db_b by editing
    let entry_b = db_b.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    set_field_and_commit(entry_b, fields::USERNAME, "historyB");
    let db_b_history_count = db_b
        .root
        .find_entry_by_uuid(entry1_uuid)
        .unwrap()
        .history
        .as_ref()
        .map_or(0, |h| h.get_entries().len());

    merge(&mut db_a, &db_b).expect("merge failed");

    let merged_entry = db_a.root.find_entry_by_uuid(entry1_uuid).unwrap();
    let history = merged_entry.history.as_ref().expect("history should exist");
    let merged_history_count = history.get_entries().len();

    // Merged history should contain entries from both sides
    // It should be at least as many as the max of the two individual histories
    assert!(
        merged_history_count >= db_a_history_count.max(db_b_history_count),
        "Merged history ({}) should be >= max individual ({}, {})",
        merged_history_count,
        db_a_history_count,
        db_b_history_count
    );
}

/// Entry exists in source but not destination -- added to merged result.
#[test]
fn test_merge_new_entry_added() {
    let base = create_base_db();
    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Add new entry to db_b (source) only
    let mut new_entry = Entry::new();
    let new_uuid = new_entry.uuid;
    new_entry.set_unprotected(fields::TITLE, "Brand New");
    new_entry.set_unprotected(fields::USERNAME, "newuser");
    db_b.root.entries.push(new_entry);

    merge(&mut db_a, &db_b).expect("merge failed");

    let found = db_a.root.find_entry_by_uuid(new_uuid);
    assert!(
        found.is_some(),
        "New entry from source should be added to destination"
    );
    assert_eq!(found.unwrap().get(fields::TITLE), Some("Brand New"));
}

/// Inverse: Entry in source but in destination's DeletedObjects -- NOT added.
#[test]
fn test_merge_new_entry_not_added_if_deleted() {
    let base = create_base_db();
    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Add new entry to db_b (source) only
    let mut new_entry = Entry::new();
    let new_uuid = new_entry.uuid;
    new_entry.set_unprotected(fields::TITLE, "Should Not Appear");
    db_b.root.entries.push(new_entry);

    // Mark that UUID as deleted in db_a's DeletedObjects
    db_a.deleted_objects.insert(new_uuid, Some(Times::now()));

    merge(&mut db_a, &db_b).expect("merge failed");

    assert!(
        db_a.root.find_entry_by_uuid(new_uuid).is_none(),
        "Entry in DeletedObjects should NOT be resurrected by merge"
    );
}

/// MergeResult counts are correct.
#[test]
fn test_merge_result_counts() {
    let base = create_base_db();
    let entry1_uuid = base.root.entries[0].uuid;

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Add a new entry in source (should count as entries_added)
    let mut new_entry = Entry::new();
    new_entry.set_unprotected(fields::TITLE, "Added Entry");
    db_b.root.entries.push(new_entry);

    // Update an existing entry in source (should count as entries_updated)
    thread::sleep(Duration::from_secs(1));
    let entry_b = db_b.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    set_field_and_commit(entry_b, fields::TITLE, "Updated Title");

    let result = merge(&mut db_a, &db_b).expect("merge failed");

    assert_eq!(
        result.entries_added, 1,
        "Should have 1 entry added, got {}",
        result.entries_added
    );
    assert!(
        result.entries_updated >= 1,
        "Should have at least 1 entry updated, got {}",
        result.entries_updated
    );
    assert!(
        result.total_changes() >= 2,
        "Total changes should be >= 2, got {}",
        result.total_changes()
    );
}

/// Same-timestamp conflict: destination wins, MergeResult exposes conflict + warning.
#[test]
fn test_merge_same_timestamp_tiebreak_destination_wins() {
    let base = create_base_db();
    let entry1_uuid = base.root.entries[0].uuid;

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Pick a single shared timestamp for both sides.
    let shared_timestamp = Times::now();

    // Both sides edit the same entry to different values, at the same timestamp.
    let entry_a = db_a.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    entry_a.set_unprotected(fields::TITLE, "Destination Title");
    entry_a.times.last_modification = Some(shared_timestamp);

    let entry_b = db_b.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    entry_b.set_unprotected(fields::TITLE, "Source Title");
    entry_b.times.last_modification = Some(shared_timestamp);

    let result = merge(&mut db_a, &db_b).expect("merge failed");

    let merged_entry = db_a.root.find_entry_by_uuid(entry1_uuid).unwrap();
    assert_eq!(
        merged_entry.get(fields::TITLE),
        Some("Destination Title"),
        "Destination version must win on same-timestamp tiebreak"
    );

    // MergeResult must expose the conflict and its resolution.
    let tiebreak_conflict = result
        .conflicts
        .iter()
        .find(|c| c.resolution == ConflictResolution::SameTimestampSelfWins)
        .expect("MergeResult.conflicts must include a SameTimestampSelfWins entry");
    assert_eq!(
        tiebreak_conflict.node_uuid, entry1_uuid,
        "Conflict UUID must identify the diverged entry"
    );

    let has_tiebreak_warning = result
        .warnings
        .iter()
        .any(|w| matches!(w, MergeWarning::SameTimestampTiebreak { node_uuid, .. } if *node_uuid == entry1_uuid));
    assert!(
        has_tiebreak_warning,
        "MergeResult.warnings must include a SameTimestampTiebreak for {entry1_uuid}"
    );
}

/// Soft-deleted entry stays in recycle bin (not resurrected) after merging an unchanged source.
#[test]
fn test_merge_soft_delete_preserved_across_merge() {
    let mut base = Database::new(DatabaseConfig::default());
    base.root.name = "Root".to_string();
    base.meta.recyclebin_enabled = Some(true);

    let mut entry = Entry::new();
    entry.set_unprotected(fields::TITLE, "To Be Recycled");
    let entry_uuid = entry.uuid;
    base.root.entries.push(entry);
    let base = round_trip(&base);

    let mut db_a = clone_db(&base);
    let db_b = clone_db(&base);

    keepassxc::delete_entry(&mut db_a, entry_uuid, true).expect("soft delete failed");
    let bin_uuid = db_a
        .meta
        .recyclebin_uuid
        .expect("recycle bin must have been created by soft delete");

    // Entry should live in the recycle bin before merge.
    let bin = db_a
        .root
        .groups
        .iter()
        .find(|g| g.uuid == bin_uuid)
        .expect("recycle bin group must exist");
    assert!(
        bin.entries.iter().any(|e| e.uuid == entry_uuid),
        "Soft-deleted entry must be in the recycle bin"
    );
    assert!(
        db_a.deleted_objects.contains_key(&entry_uuid),
        "Soft delete must record the entry in deleted_objects"
    );

    merge(&mut db_a, &db_b).expect("merge failed");

    // After merging a source that still has the entry in root, the destination's
    // recycle-bin placement and deleted_objects tombstone must survive.
    let bin_after = db_a
        .root
        .groups
        .iter()
        .find(|g| g.uuid == bin_uuid)
        .expect("recycle bin group must still exist");
    assert!(
        bin_after.entries.iter().any(|e| e.uuid == entry_uuid),
        "Soft-deleted entry must remain in the recycle bin after merge"
    );
    assert!(
        !db_a.root.entries.iter().any(|e| e.uuid == entry_uuid),
        "Soft-deleted entry must not be resurrected at the root after merge"
    );
    assert!(
        db_a.deleted_objects.contains_key(&entry_uuid),
        "deleted_objects tombstone must survive merge"
    );
}

/// Source has a newer tombstone for an entry still present in destination:
/// merge must remove the entry and propagate the tombstone.
#[test]
fn test_merge_propagates_source_deletion() {
    let base = create_base_db();
    let entry_uuid = base.root.entries[0].uuid;

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Give the source a deletion timestamp strictly newer than the destination
    // entry's last_modification (round-trip establishes that timestamp in the past).
    thread::sleep(Duration::from_secs(1));
    let deletion_time = Times::now();
    db_b.deleted_objects.insert(entry_uuid, Some(deletion_time));

    let result = merge(&mut db_a, &db_b).expect("merge failed");

    assert!(
        db_a.root.find_entry_by_uuid(entry_uuid).is_none(),
        "Entry must be removed when source has a newer deletion tombstone"
    );
    assert!(
        db_a.deleted_objects.contains_key(&entry_uuid),
        "Destination must adopt the source's deletion tombstone"
    );
    assert!(
        result.entries_deleted >= 1,
        "MergeResult.entries_deleted must count the propagated deletion, got {}",
        result.entries_deleted
    );
}

/// Merge result survives a full save/reopen cycle through ManyKee.
#[test]
fn test_merge_output_round_trips_through_manykee() {
    let base = create_base_db();
    let entry1_uuid = base.root.entries[0].uuid;

    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    // Source adds a new entry and updates an existing one.
    let mut new_entry = Entry::new();
    new_entry.set_unprotected(fields::TITLE, "Post-Merge Entry");
    new_entry.set_unprotected(fields::USERNAME, "postmerge");
    let new_uuid = new_entry.uuid;
    db_b.root.entries.push(new_entry);

    thread::sleep(Duration::from_secs(1));
    let entry_b = db_b.root.entry_by_uuid_mut(entry1_uuid).unwrap();
    set_field_and_commit(entry_b, fields::USERNAME, "source-user");

    merge(&mut db_a, &db_b).expect("merge failed");

    // Save the merged db, reopen it, and confirm both entries survived cleanly.
    let reopened = round_trip(&db_a);
    let reopened_new = reopened
        .root
        .find_entry_by_uuid(new_uuid)
        .expect("new entry must survive save/reopen");
    assert_eq!(
        reopened_new.get(fields::TITLE),
        Some("Post-Merge Entry"),
        "New entry title must survive save/reopen after merge"
    );
    let reopened_existing = reopened
        .root
        .find_entry_by_uuid(entry1_uuid)
        .expect("existing entry must survive save/reopen");
    assert_eq!(
        reopened_existing.get(fields::USERNAME),
        Some("source-user"),
        "Source-side edit must survive save/reopen after merge"
    );

    // History retention must also survive the save/reopen.
    let history = reopened_existing
        .history
        .as_ref()
        .expect("history must survive save/reopen");
    assert!(
        !history.get_entries().is_empty(),
        "History must retain at least one prior version after save/reopen"
    );
}

/// Merged output opens cleanly through keepassxc-cli when the 2.7.12 tool is
/// available. Gated on MANYKEE_REQUIRE_OFFICIAL_TOOLS: skips otherwise, matching
/// the rest of the keepassxc integration test suite.
#[test]
fn test_merge_output_opens_in_keepassxc() {
    let Some(tool) = keepassxc_tool_or_skip() else {
        return;
    };

    let base = create_base_db();
    let mut db_a = clone_db(&base);
    let mut db_b = clone_db(&base);

    let mut new_entry = Entry::new();
    new_entry.set_unprotected(fields::TITLE, "Merged Entry");
    new_entry.set_unprotected(fields::USERNAME, "mergeduser");
    db_b.root.entries.push(new_entry);

    merge(&mut db_a, &db_b).expect("merge failed");

    let dir = tempfile::tempdir().expect("tempdir failed");
    let path = dir.path().join("merged.kdbx");
    let mut file = std::fs::File::create(&path).expect("create failed");
    db_a.save(&mut file, make_key()).expect("save failed");
    drop(file);

    let output = keepassxc_cli_ls(&tool, &path, TEST_PASSWORD);
    assert!(
        output.status.success(),
        "keepassxc-cli ls must succeed on merged output:\nstdout: {}\nstderr: {}",
        output.stdout,
        output.stderr
    );
    assert!(
        output.stdout.contains("Merged Entry"),
        "keepassxc-cli ls must surface the merged entry, got:\n{}",
        output.stdout
    );
}

fn keepassxc_tool_or_skip() -> Option<OfficialTool> {
    match discover_keepassxc(mode_from_env()) {
        Ok(Some(tool)) => {
            debug_assert_eq!(tool.version, REQUIRED_KEEPASSXC_VERSION);
            Some(tool)
        }
        Ok(None) => {
            eprintln!(
                "SKIP: keepassxc-cli 2.7.12 not available; set MANYKEE_REQUIRE_OFFICIAL_TOOLS=1 to fail instead"
            );
            None
        }
        Err(err) => panic!("{err}"),
    }
}

fn keepassxc_cli_ls(tool: &OfficialTool, db_path: &Path, password: &str) -> RedactedOutput {
    let args = vec![
        OsString::from("ls"),
        OsString::from("-R"),
        OsString::from("-f"),
        db_path.as_os_str().to_os_string(),
    ];
    run_keepassxc_with_stdin_lines(tool, &args, &[password], &[password])
        .unwrap_or_else(|err| panic!("{err}"))
}
