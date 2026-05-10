use keepass::config::DatabaseConfig;
use keepass::db::{
    fields, Attachment, AutoType, AutoTypeAssociation, CustomDataItem, CustomDataValue, Database,
    Entry, Group, History, MemoryProtection, Times, Value,
};
use keepass::DatabaseKey;
use keepassxc::semantic_snapshot::{snapshot_database, snapshot_json_pretty};
use std::fs::File;
use std::path::{Path, PathBuf};
use uuid::Uuid;

fn stable_uuid(value: u128) -> Uuid {
    Uuid::from_u128(value)
}

fn stable_times() -> Times {
    let epoch = Times::epoch();
    let mut times = Times::new();
    times.creation = Some(epoch);
    times.last_modification = Some(epoch);
    times.last_access = Some(epoch);
    times.expiry = Some(epoch);
    times.location_changed = Some(epoch);
    times.expires = Some(false);
    times.usage_count = Some(7);
    times
}

fn string_custom_data(value: &str) -> CustomDataItem {
    CustomDataItem {
        value: Some(CustomDataValue::String(value.to_string())),
        last_modification_time: Some(Times::epoch()),
        unknown_xml: Vec::new(),
    }
}

fn binary_custom_data(bytes: &[u8]) -> CustomDataItem {
    CustomDataItem {
        value: Some(CustomDataValue::Binary(bytes.to_vec())),
        last_modification_time: Some(Times::epoch()),
        unknown_xml: Vec::new(),
    }
}

fn build_fid01_database() -> Database {
    let mut db = Database::new(DatabaseConfig::default());
    db.meta.generator = Some("ManyKee semantic snapshot test".to_string());
    db.meta.database_name = Some("FID-01 coverage".to_string());
    db.meta.database_description = Some("Synthetic semantic snapshot database".to_string());
    db.meta.default_username = Some("default-user".to_string());
    db.meta.maintenance_history_days = Some(365);
    db.meta.master_key_change_rec = Some(30);
    db.meta.master_key_change_force = Some(60);
    db.meta.history_max_items = Some(10);
    db.meta.history_max_size = Some(4096);
    db.meta.recyclebin_enabled = Some(true);
    db.meta.recyclebin_uuid = Some(stable_uuid(0xaaaaaaaa_aaaa_aaaa_aaaa_aaaaaaaaaaaa));
    db.meta.settings_changed = Some(Times::epoch());
    db.meta.memory_protection = Some(MemoryProtection {
        protect_title: false,
        protect_username: false,
        protect_password: true,
        protect_url: false,
        protect_notes: false,
    });
    db.meta
        .custom_data
        .insert("meta-string".to_string(), string_custom_data("meta-value"));
    db.meta
        .custom_data
        .insert("meta-binary".to_string(), binary_custom_data(b"meta-bytes"));

    db.root.uuid = stable_uuid(0x10000000_0000_0000_0000_000000000001);
    db.root.name = "Root".to_string();
    db.root.notes = Some("root notes".to_string());
    db.root.icon_id = Some(48);
    db.root.custom_icon_uuid = Some(stable_uuid(0xbbbbbbbb_bbbb_bbbb_bbbb_bbbbbbbbbbbb));
    db.root.tags = Some("root-tag;shared".to_string());
    db.root.times = stable_times();
    db.root.custom_data.insert(
        "group-custom".to_string(),
        string_custom_data("root-custom"),
    );

    let mut child = Group::new("Child");
    child.uuid = stable_uuid(0x10000000_0000_0000_0000_000000000002);
    child.notes = Some("child notes".to_string());
    child.tags = Some("child-tag".to_string());
    child.times = stable_times();
    child.custom_data.insert(
        "child-custom".to_string(),
        string_custom_data("child-value"),
    );

    let mut entry = Entry::new();
    entry.uuid = stable_uuid(0x20000000_0000_0000_0000_000000000001);
    entry.times = stable_times();
    entry.set_unprotected(fields::TITLE, "Snapshot Entry");
    entry.set_unprotected(fields::USERNAME, "snapshot-user");
    entry.set_protected(fields::PASSWORD, "synthetic-password");
    entry.set_unprotected(fields::URL, "https://example.test/login");
    entry.set_unprotected(fields::NOTES, "synthetic notes");
    entry.fields.insert(
        "custom-visible".to_string(),
        Value::unprotected("custom value".to_string()),
    );
    entry.fields.insert(
        "custom-secret".to_string(),
        Value::protected("custom secret".to_string()),
    );
    entry.tags = vec!["important".to_string(), "work".to_string()];
    entry.autotype = Some(AutoType {
        enabled: true,
        default_sequence: Some("{USERNAME}{TAB}{PASSWORD}{ENTER}".to_string()),
        data_transfer_obfuscation: Some(true),
        associations: vec![AutoTypeAssociation {
            window: "Example Login".to_string(),
            sequence: "{USERNAME}{TAB}{PASSWORD}{ENTER}".to_string(),
        }],
    });
    entry.attachments.insert(
        "public.txt".to_string(),
        Attachment {
            data: Value::unprotected(b"public attachment".to_vec()),
        },
    );
    entry.attachments.insert(
        "secret.bin".to_string(),
        Attachment {
            data: Value::protected(b"secret attachment".to_vec()),
        },
    );
    entry.custom_icon = Some((
        stable_uuid(0xcccccccc_cccc_cccc_cccc_cccccccccccc),
        b"custom-icon-bytes".to_vec(),
    ));
    entry.custom_data.insert(
        "entry-string".to_string(),
        string_custom_data("entry-value"),
    );
    entry.custom_data.insert(
        "entry-binary".to_string(),
        binary_custom_data(b"entry-bytes"),
    );
    let mut previous = entry.clone();
    previous.set_protected(fields::PASSWORD, "previous-password");
    previous.history = None;
    let mut history = History::default();
    history.add_entry(previous);
    entry.history = Some(history);

    let deleted_uuid = stable_uuid(0xdddddddd_dddd_dddd_dddd_dddddddddddd);
    db.deleted_objects
        .insert(deleted_uuid, Some(Times::epoch()));

    child.entries.push(entry);
    db.root.groups.push(child);
    db
}

fn build_fid01_database_with_alternate_insertion_order() -> Database {
    let mut db = build_fid01_database();

    db.meta.custom_data.clear();
    db.meta
        .custom_data
        .insert("meta-binary".to_string(), binary_custom_data(b"meta-bytes"));
    db.meta
        .custom_data
        .insert("meta-string".to_string(), string_custom_data("meta-value"));

    db.root.custom_data.clear();
    db.root.custom_data.insert(
        "group-custom".to_string(),
        string_custom_data("root-custom"),
    );

    let child = db.root.groups.first_mut().expect("child group exists");
    child.custom_data.clear();
    child.custom_data.insert(
        "child-custom".to_string(),
        string_custom_data("child-value"),
    );

    let entry = child.entries.first_mut().expect("entry exists");
    entry.fields.clear();
    entry.fields.insert(
        "custom-secret".to_string(),
        Value::protected("custom secret".to_string()),
    );
    entry.fields.insert(
        "custom-visible".to_string(),
        Value::unprotected("custom value".to_string()),
    );
    entry.set_unprotected(fields::NOTES, "synthetic notes");
    entry.set_unprotected(fields::URL, "https://example.test/login");
    entry.set_protected(fields::PASSWORD, "synthetic-password");
    entry.set_unprotected(fields::USERNAME, "snapshot-user");
    entry.set_unprotected(fields::TITLE, "Snapshot Entry");

    entry.custom_data.clear();
    entry
        .custom_data
        .insert("entry-binary".to_string(), binary_custom_data(b"entry-bytes"));
    entry
        .custom_data
        .insert("entry-string".to_string(), string_custom_data("entry-value"));

    entry.attachments.clear();
    entry.attachments.insert(
        "secret.bin".to_string(),
        Attachment {
            data: Value::protected(b"secret attachment".to_vec()),
        },
    );
    entry.attachments.insert(
        "public.txt".to_string(),
        Attachment {
            data: Value::unprotected(b"public attachment".to_vec()),
        },
    );
    entry.tags = vec!["work".to_string(), "important".to_string()];

    db
}

fn richcontent_fixture_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/resources/test_db_kdbx4_richcontent.kdbx")
}

#[test]
fn snapshot_covers_fid01_fields() {
    let db = build_fid01_database();
    let snapshot = snapshot_database(&db);

    assert_eq!(snapshot.schema_version, 1);
    assert_eq!(snapshot.root_group.name, "Root");
    assert!(snapshot
        .groups
        .iter()
        .any(|group| group.name == "Child" && group.path == "/Root/Child"));

    let entry = snapshot
        .entries
        .iter()
        .find(|entry| entry.path == "/Root/Child/Snapshot Entry")
        .expect("entry snapshot should include nested entry path");

    for standard_field in [
        fields::TITLE,
        fields::USERNAME,
        fields::PASSWORD,
        fields::URL,
        fields::NOTES,
    ] {
        assert!(
            entry.fields.contains_key(standard_field),
            "missing standard field {standard_field}"
        );
    }

    assert_eq!(entry.fields[fields::PASSWORD].value, "synthetic-password");
    assert!(entry.fields[fields::PASSWORD].protected);
    assert!(!entry.fields[fields::TITLE].protected);
    assert_eq!(entry.fields["custom-visible"].value, "custom value");
    assert!(entry.fields["custom-secret"].protected);

    assert_eq!(entry.tags, vec!["important", "work"]);
    assert_eq!(
        snapshot.metadata.memory_protection.protect_password,
        Some(true)
    );
    assert!(snapshot.metadata.custom_data.contains_key("meta-string"));
    assert!(snapshot.metadata.custom_data.contains_key("meta-binary"));
    assert_eq!(snapshot.root_group.tags.as_deref(), Some("root-tag;shared"));
    assert!(snapshot.root_group.custom_data.contains_key("group-custom"));
    assert!(entry.custom_data.contains_key("entry-string"));
    assert!(entry.custom_data.contains_key("entry-binary"));
    assert!(entry.times.creation.is_some());

    let public_attachment = entry
        .attachments
        .iter()
        .find(|attachment| attachment.name == "public.txt")
        .expect("public attachment should be snapshotted");
    assert!(!public_attachment.protected);
    assert_eq!(public_attachment.size, b"public attachment".len());
    assert_eq!(public_attachment.sha256.len(), 64);
    assert!(
        public_attachment
            .sha256
            .chars()
            .all(|ch| ch.is_ascii_hexdigit() && !ch.is_ascii_uppercase()),
        "attachment hash must be lowercase hex"
    );

    let secret_attachment = entry
        .attachments
        .iter()
        .find(|attachment| attachment.name == "secret.bin")
        .expect("protected attachment should be snapshotted");
    assert!(secret_attachment.protected);
    assert_eq!(secret_attachment.size, b"secret attachment".len());

    let autotype = entry
        .autotype
        .as_ref()
        .expect("Auto-Type metadata should be snapshotted");
    assert!(autotype.enabled);
    assert_eq!(
        autotype.default_sequence.as_deref(),
        Some("{USERNAME}{TAB}{PASSWORD}{ENTER}")
    );
    assert_eq!(autotype.associations.len(), 1);

    let custom_icon = entry
        .custom_icon
        .as_ref()
        .expect("custom icon should be snapshotted");
    assert_eq!(custom_icon.size, b"custom-icon-bytes".len());
    assert_eq!(custom_icon.sha256.len(), 64);

    assert_eq!(entry.history.len(), 1);
    assert_eq!(snapshot.deleted_objects.len(), 1);
    assert!(snapshot
        .unsupported
        .contains_key("unknown_xml_outer_attributes"));
    assert!(snapshot
        .unsupported
        .contains_key("unknown_xml_direct_test_construction"));
    assert!(snapshot
        .unsupported
        .contains_key("unreferenced_custom_icon_pool"));
    assert!(snapshot.not_observed.contains_key("public_custom_data"));
}

#[test]
fn snapshot_is_deterministic() {
    let first = snapshot_json_pretty(&build_fid01_database()).expect("snapshot should serialize");
    let second = snapshot_json_pretty(&build_fid01_database_with_alternate_insertion_order())
        .expect("snapshot should serialize");

    assert_eq!(first, second);
}

#[test]
fn richcontent_fixture_snapshot_smoke() {
    let fixture_path = richcontent_fixture_path();
    if !fixture_path.exists() {
        panic!("Fixture not found: {}", fixture_path.display());
    }

    let key = DatabaseKey::new().with_password("testpass123");
    let db = Database::open(
        &mut File::open(&fixture_path).expect("failed to open richcontent fixture file"),
        key,
    )
    .expect("failed to decrypt richcontent fixture");

    let snapshot = snapshot_database(&db);
    assert!(
        !snapshot.groups.is_empty() || !snapshot.entries.is_empty(),
        "fixture snapshot should include group or entry evidence"
    );
    assert!(
        snapshot.metadata.database_name.is_some()
            || snapshot.metadata.generator.is_some()
            || snapshot.metadata.database_description.is_some(),
        "fixture snapshot should include metadata evidence"
    );
    assert!(
        !snapshot.metadata.custom_data.is_empty()
            || snapshot
                .groups
                .iter()
                .any(|group| !group.custom_data.is_empty())
            || snapshot
                .entries
                .iter()
                .any(|entry| !entry.custom_data.is_empty()),
        "fixture snapshot should include custom data evidence"
    );
}
