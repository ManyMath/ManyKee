use std::fs::File;
use std::path::Path;

use keepass::config::DatabaseVersion;
use keepassxc::{
    create_group, fields, move_entry, move_group, read_entry_fields, rename_group, save_atomic,
    update_entry, CustomDataItem, CustomDataValue, Database, DatabaseConfig, DatabaseKey, Entry,
    EntryExt, GroupExt,
};
use tempfile::TempDir;

fn make_db() -> (Database, uuid::Uuid, uuid::Uuid, uuid::Uuid, uuid::Uuid) {
    let mut db = Database::new(DatabaseConfig::default());
    let root_uuid = db.root.uuid;
    let source_uuid = create_group(&mut db.root, root_uuid, "Source").unwrap();
    let target_uuid = create_group(&mut db.root, root_uuid, "Target").unwrap();
    let nested_uuid = create_group(&mut db.root, source_uuid, "Nested").unwrap();

    let mut entry = Entry::new();
    entry.set_unprotected(fields::TITLE, "Writable Entry");
    entry.custom_data.insert(
        "otp".to_string(),
        CustomDataItem {
            value: Some(CustomDataValue::String(
                "otpauth://totp/ManyKee:test?secret=JBSWY3DPEHPK3PXP".to_string(),
            )),
            last_modification_time: None,
        },
    );
    let entry_uuid = entry.uuid;
    db.root
        .find_group_by_uuid_mut(source_uuid)
        .unwrap()
        .add_entry(entry);

    update_entry(&mut db.root, entry_uuid, &db.meta.clone(), |entry| {
        entry.set_unprotected(fields::USERNAME, "writer");
    })
    .unwrap();

    (db, source_uuid, target_uuid, nested_uuid, entry_uuid)
}

fn reopen(path: &Path, password: &str) -> Database {
    Database::open(
        &mut File::open(path).expect("open saved database"),
        DatabaseKey::new().with_password(password),
    )
    .expect("reopen saved database")
}

#[test]
fn move_entry_preserves_timestamps_round_trip() {
    let (mut db, source_uuid, target_uuid, _, entry_uuid) = make_db();
    let before = db
        .root
        .find_entry_by_uuid(entry_uuid)
        .unwrap()
        .times
        .last_modification;
    let history_len = db
        .root
        .find_entry_by_uuid(entry_uuid)
        .unwrap()
        .history
        .as_ref()
        .unwrap()
        .get_entries()
        .len();

    move_entry(&mut db.root, entry_uuid, target_uuid).unwrap();

    let tmp = TempDir::new().unwrap();
    let path = tmp.path().join("move-entry.kdbx");
    save_atomic(&db, &path, DatabaseKey::new().with_password("test")).unwrap();
    let reopened = reopen(&path, "test");

    assert!(reopened
        .root
        .find_group_by_uuid(source_uuid)
        .unwrap()
        .entries
        .iter()
        .all(|entry| entry.uuid != entry_uuid));
    let moved = reopened.root.find_entry_by_uuid(entry_uuid).unwrap();
    assert_eq!(moved.times.last_modification, before);
    assert_eq!(
        moved.history.as_ref().unwrap().get_entries().len(),
        history_len
    );
    assert_eq!(moved.previous_parent_group, Some(source_uuid));
}

#[test]
fn move_entry_missing_target_fails() {
    let (mut db, _, _, _, entry_uuid) = make_db();
    let error = move_entry(&mut db.root, entry_uuid, uuid::Uuid::new_v4()).unwrap_err();
    assert!(matches!(error, keepassxc::KeePassXcError::GroupNotFound(_)));
}

#[test]
fn move_group_with_entries_round_trip() {
    let (mut db, source_uuid, target_uuid, nested_uuid, entry_uuid) = make_db();
    move_group(&mut db.root, source_uuid, target_uuid).unwrap();

    let tmp = TempDir::new().unwrap();
    let path = tmp.path().join("move-group.kdbx");
    save_atomic(&db, &path, DatabaseKey::new().with_password("test")).unwrap();
    let reopened = reopen(&path, "test");

    let moved_group = reopened.root.find_group_by_uuid(source_uuid).unwrap();
    assert_eq!(moved_group.previous_parent_group, Some(reopened.root.uuid));
    assert!(moved_group.find_group_by_uuid(nested_uuid).is_some());
    assert!(moved_group.find_entry_by_uuid(entry_uuid).is_some());
    assert!(reopened
        .root
        .find_group_by_uuid(target_uuid)
        .unwrap()
        .find_group_by_uuid(source_uuid)
        .is_some());
}

#[test]
fn move_group_into_self_fails() {
    let (mut db, source_uuid, _, _, _) = make_db();
    let error = move_group(&mut db.root, source_uuid, source_uuid).unwrap_err();
    assert!(error.to_string().contains("itself"));
}

#[test]
fn save_atomic_creates_reopenable_file() {
    let (db, _, _, _, _) = make_db();
    let tmp = TempDir::new().unwrap();
    let path = tmp.path().join("saved.kdbx");
    save_atomic(&db, &path, DatabaseKey::new().with_password("test")).unwrap();
    assert!(path.exists());

    let reopened = reopen(&path, "test");
    assert!(reopened
        .root
        .find_group_by_uuid(reopened.root.uuid)
        .is_some());
}

#[test]
fn save_atomic_failure_leaves_original_untouched() {
    let (db, _, _, _, _) = make_db();
    let tmp = TempDir::new().unwrap();
    let path = tmp.path().join("original.kdbx");
    save_atomic(&db, &path, DatabaseKey::new().with_password("test")).unwrap();
    let original = std::fs::read(&path).unwrap();

    let mut invalid = db.clone();
    invalid.config.version = DatabaseVersion::KDB3(1);
    let error = save_atomic(&invalid, &path, DatabaseKey::new().with_password("test")).unwrap_err();

    assert!(error.to_string().contains("Unsupported"));
    assert_eq!(std::fs::read(&path).unwrap(), original);
}

#[test]
fn read_entry_fields_surfaces_custom_data() {
    let (db, _, _, _, entry_uuid) = make_db();
    let payload = read_entry_fields(db.root.find_entry_by_uuid(entry_uuid).unwrap());

    assert_eq!(
        payload.fields.get(fields::TITLE).map(String::as_str),
        Some("Writable Entry")
    );
    assert_eq!(
        payload.custom_data.get("otp").map(String::as_str),
        Some("otpauth://totp/ManyKee:test?secret=JBSWY3DPEHPK3PXP")
    );
}

#[test]
fn rename_group_updates_name() {
    let (mut db, source_uuid, _, _, _) = make_db();
    rename_group(&mut db.root, source_uuid, "Renamed Source").unwrap();
    assert_eq!(
        db.root.find_group_by_uuid(source_uuid).unwrap().name,
        "Renamed Source"
    );
}
