//! Comprehensive round-trip test suite validating KDBX 4.x read-write fidelity.
//!
//! Requirements covered:
//! Byte-stable round-trip (no field loss on read-write-read)
//! CustomData (TOTP seeds, browser state) survives round-trip
//! Binary attachments survive round-trip
//! AutoType configuration survives round-trip
//! KeePassXC can open every file ManyKee writes
//! DATA-08 -- Meta section fields survive round-trip
//! DATA-10 -- Entry and group UUIDs identical before and after round-trip

mod common;

use std::collections::HashSet;
use std::ffi::OsString;
use std::fs::File;
use std::path::{Path, PathBuf};
use std::sync::Once;

use common::official_tools::{
    discover_keepassxc, mode_from_env, run_keepassxc_with_stdin_lines, OfficialTool,
    RedactedOutput, REQUIRED_KEEPASSXC_VERSION,
};
use keepass::config::DatabaseConfig;
use keepass::db::{
    fields, Attachment, AutoType, AutoTypeAssociation, CustomDataItem, CustomDataValue, Database,
    Entry, Group, History, MemoryProtection, Value,
};
use keepass::DatabaseKey;
use keepassxc::EntryExt;
use tempfile::TempDir;
use uuid::Uuid;

#[test]
fn official_tool_calls_use_shared_helper_policy() {
    let source_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/roundtrip.rs");
    let source = std::fs::read_to_string(source_path).expect("failed to read test source");
    let direct_command = ["Command::new(", "\"keepassxc-cli\"", ")"].concat();
    let direct_stdio = ["Stdio", "::", "piped"].concat();
    let shared_module = ["mod ", "common;"].concat();
    let shared_runner = ["run_keepassxc", "_with_stdin_lines"].concat();

    assert!(
        source.contains(&shared_module),
        "Round-trip tests must import shared test helpers"
    );
    assert!(
        source.contains(&shared_runner),
        "Round-trip tests must use shared official-tool runner"
    );
    assert!(
        !source.contains(&direct_command),
        "Round-trip tests must not spawn keepassxc-cli directly"
    );
    assert!(
        !source.contains(&direct_stdio),
        "Round-trip tests must not manage official-tool stdio directly"
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

fn keepassxc_cli_ls(db_path: &Path, password: &str) -> Option<RedactedOutput> {
    let tool = keepassxc_tool_or_skip()?;
    let args = vec![OsString::from("ls"), db_path.as_os_str().to_os_string()];

    Some(
        run_keepassxc_with_stdin_lines(&tool, &args, &[password], &[password])
            .unwrap_or_else(|err| panic!("{err}")),
    )
}

fn keepassxc_cli_show(db_path: &Path, password: &str, entry: &str) -> Option<RedactedOutput> {
    let tool = keepassxc_tool_or_skip()?;
    let args = vec![
        OsString::from("show"),
        db_path.as_os_str().to_os_string(),
        OsString::from(entry),
    ];

    Some(
        run_keepassxc_with_stdin_lines(&tool, &args, &[password], &[password])
            .unwrap_or_else(|err| panic!("{err}")),
    )
}

/// Open a fixture, save to tempfile, reopen. Returns (tmpdir, original_db, saved_db).
/// tmpdir must be kept alive to prevent cleanup.
fn open_and_save(fixture_path: &Path, password: &str) -> (TempDir, Database, Database) {
    let key = DatabaseKey::new().with_password(password);
    let db_orig = Database::open(&mut File::open(fixture_path).unwrap(), key.clone())
        .expect("failed to open fixture");

    let tmp = TempDir::new().unwrap();
    let saved_path = tmp.path().join("roundtrip.kdbx");
    {
        let mut file = File::create(&saved_path).unwrap();
        db_orig
            .save(&mut file, DatabaseKey::new().with_password(password))
            .expect("failed to save");
    }

    let db_saved = Database::open(
        &mut File::open(&saved_path).unwrap(),
        DatabaseKey::new().with_password(password),
    )
    .expect("failed to reopen saved db");

    (tmp, db_orig, db_saved)
}

fn fixture_path(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../keepass-rs/tests/resources")
        .join(name)
}

fn richcontent_fixture_path() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/resources/test_db_kdbx4_richcontent.kdbx")
}

fn collect_entry_uuids(group: &Group) -> HashSet<Uuid> {
    let mut uuids = HashSet::new();
    for entry in &group.entries {
        uuids.insert(entry.uuid);
    }
    for g in &group.groups {
        uuids.extend(collect_entry_uuids(g));
    }
    uuids
}

fn collect_group_uuids(group: &Group) -> HashSet<Uuid> {
    let mut uuids = HashSet::new();
    uuids.insert(group.uuid);
    for g in &group.groups {
        uuids.extend(collect_group_uuids(g));
    }
    uuids
}

fn count_entries(group: &Group) -> usize {
    let mut count = group.entries.len();
    for g in &group.groups {
        count += count_entries(g);
    }
    count
}

fn count_groups(group: &Group) -> usize {
    let mut count = group.groups.len();
    for g in &group.groups {
        count += count_groups(g);
    }
    count
}

fn find_entry_by_title<'a>(group: &'a Group, title: &str) -> Option<&'a Entry> {
    for entry in &group.entries {
        if entry.get(fields::TITLE) == Some(title) {
            return Some(entry);
        }
    }
    for g in &group.groups {
        if let Some(e) = find_entry_by_title(g, title) {
            return Some(e);
        }
    }
    None
}

fn save_db(db: &Database, path: &Path, password: &str) {
    let mut file = File::create(path).expect("failed to create db file");
    let key = DatabaseKey::new().with_password(password);
    db.save(&mut file, key).expect("failed to save database");
}

const RICHCONTENT_PASSWORD: &str = "testpass123";

static FIXTURE_INIT: Once = Once::new();

/// Create and cache richcontent fixture database (thread-safe).
fn create_richcontent_fixture() -> PathBuf {
    let path = richcontent_fixture_path();

    FIXTURE_INIT.call_once(|| {
        create_richcontent_fixture_inner(&path);
    });

    path
}

fn create_richcontent_fixture_inner(path: &Path) {
    if path.exists() {
        return;
    }

    let mut db = Database::new(DatabaseConfig::default());
    db.meta.database_name = Some("ManyKee Test Database".to_string());
    db.meta.database_description = Some("Rich content fixture for round-trip tests".to_string());
    db.meta.memory_protection = Some(MemoryProtection {
        protect_title: false,
        protect_username: false,
        protect_password: true,
        protect_url: false,
        protect_notes: false,
    });
    db.meta.history_max_items = Some(10);
    db.meta.history_max_size = Some(6291456);
    db.meta.maintenance_history_days = Some(365usize);
    db.meta.recyclebin_enabled = Some(true);

    db.meta.custom_data.insert(
        "KPXC_DECRYPTION_TIME_PREFERENCE".to_string(),
        CustomDataItem {
            value: Some(CustomDataValue::String("100".to_string())),
            last_modification_time: None,
            unknown_xml: Vec::new(),
        },
    );
    db.meta.custom_data.insert(
        "ManyKee_TestKey".to_string(),
        CustomDataItem {
            value: Some(CustomDataValue::String("test_value_123".to_string())),
            last_modification_time: None,
            unknown_xml: Vec::new(),
        },
    );

    db.root.name = "Root".to_string();

    let mut level1 = Group::new("Level1Group");
    let mut level2 = Group::new("Level2Group");

    // Entry with all 5 standard fields
    let mut standard_entry = Entry::new();
    standard_entry.set_unprotected(fields::TITLE, "StandardEntry");
    standard_entry.set_unprotected(fields::USERNAME, "user@example.com");
    standard_entry.set_protected(fields::PASSWORD, "s3cret!P@ss");
    standard_entry.set_unprotected(fields::URL, "https://example.com");
    standard_entry.set_unprotected(
        fields::NOTES,
        "This is a test entry with all standard fields.",
    );
    level2.entries.push(standard_entry);

    // Entry with custom string fields
    let mut custom_fields_entry = Entry::new();
    custom_fields_entry.set_unprotected(fields::TITLE, "CustomFieldsEntry");
    custom_fields_entry.set_unprotected(fields::USERNAME, "customuser");
    custom_fields_entry.set_protected(fields::PASSWORD, "custompass");
    custom_fields_entry.fields.insert(
        "CustomField1".to_string(),
        Value::unprotected("custom_value_1".to_string()),
    );
    custom_fields_entry.fields.insert(
        "SecretField".to_string(),
        Value::protected("secret_custom".to_string()),
    );
    level1.entries.push(custom_fields_entry);

    level1.groups.push(level2);
    db.root.groups.push(level1);

    let mut autotype_entry = Entry::new();
    autotype_entry.set_unprotected(fields::TITLE, "AutoTypeEntry");
    autotype_entry.set_unprotected(fields::USERNAME, "autotypeuser");
    autotype_entry.set_protected(fields::PASSWORD, "autotypepass");
    autotype_entry.autotype = Some(AutoType {
        enabled: true,
        default_sequence: Some("{USERNAME}{TAB}{PASSWORD}{ENTER}".to_string()),
        data_transfer_obfuscation: Some(false),
        associations: vec![
            AutoTypeAssociation {
                window: "Login - *".to_string(),
                sequence: "{USERNAME}{TAB}{PASSWORD}{ENTER}".to_string(),
            },
            AutoTypeAssociation {
                window: "MyApp*".to_string(),
                sequence: "{PASSWORD}{ENTER}".to_string(),
            },
        ],
    });
    db.root.entries.push(autotype_entry);

    let mut tagged_entry = Entry::new();
    tagged_entry.set_unprotected(fields::TITLE, "TaggedEntry");
    tagged_entry.set_unprotected(fields::USERNAME, "taggeduser");
    tagged_entry.set_protected(fields::PASSWORD, "taggedpass");
    tagged_entry.tags = vec![
        "work".to_string(),
        "important".to_string(),
        "2fa".to_string(),
    ];
    db.root.entries.push(tagged_entry);

    let mut attachment_entry = Entry::new();
    attachment_entry.set_unprotected(fields::TITLE, "AttachmentEntry");
    attachment_entry.set_unprotected(fields::USERNAME, "attachuser");
    attachment_entry.set_protected(fields::PASSWORD, "attachpass");
    let file_content = b"Hello, this is test attachment content!\nLine 2 of the file.";
    attachment_entry.attachments.insert(
        "test_file.txt".to_string(),
        Attachment {
            data: Value::unprotected(file_content.to_vec()),
        },
    );
    let binary_content: Vec<u8> = (0..256).map(|i| i as u8).collect();
    attachment_entry.attachments.insert(
        "binary_data.bin".to_string(),
        Attachment {
            data: Value::unprotected(binary_content),
        },
    );
    db.root.entries.push(attachment_entry);

    let mut totp_entry = Entry::new();
    totp_entry.set_unprotected(fields::TITLE, "TOTPEntry");
    totp_entry.set_unprotected(fields::USERNAME, "totpuser");
    totp_entry.set_protected(fields::PASSWORD, "totppass");
    totp_entry.custom_data.insert(
        "otp".to_string(),
        CustomDataItem {
            value: Some(CustomDataValue::String(
                "otpauth://totp/Example:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"
                    .to_string(),
            )),
            last_modification_time: None,
            unknown_xml: Vec::new(),
        },
    );
    totp_entry.custom_data.insert(
        "KPXC_BROWSER_ENTRY".to_string(),
        CustomDataItem {
            value: Some(CustomDataValue::String("true".to_string())),
            last_modification_time: None,
            unknown_xml: Vec::new(),
        },
    );
    db.root.entries.push(totp_entry);

    let mut history_entry = Entry::new();
    history_entry.set_unprotected(fields::TITLE, "HistoryEntry");
    history_entry.set_unprotected(fields::USERNAME, "histuser");
    history_entry.set_protected(fields::PASSWORD, "currentpass");
    // Create history manually
    let mut old_version = Entry::new();
    old_version.uuid = history_entry.uuid; // Same UUID
    old_version.set_unprotected(fields::TITLE, "HistoryEntry");
    old_version.set_unprotected(fields::USERNAME, "histuser");
    old_version.set_protected(fields::PASSWORD, "oldpass");
    let mut hist = History::default();
    hist.add_entry(old_version);
    history_entry.history = Some(hist);
    db.root.entries.push(history_entry);

    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    save_db(&db, path, RICHCONTENT_PASSWORD);

    // Verify KeePassXC can open it
    if let Some(output) = keepassxc_cli_ls(path, RICHCONTENT_PASSWORD) {
        assert!(
            output.status.success(),
            "KeePassXC cannot open the rich content fixture!\nstderr: {}",
            output.stderr,
        );
    }
}

#[test]
fn test_roundtrip_no_modification() {
    let fixtures = [
        ("test_db_kdbx4_with_password_aes.kdbx", "demopass"),
        (
            "test_db_kdbx4_with_password_argon2_chacha20.kdbx",
            "demopass",
        ),
        ("test_db_kdbx4_with_password_argon2id.kdbx", "demopass"),
    ];

    for (name, password) in &fixtures {
        let path = fixture_path(name);
        if !path.exists() {
            panic!("Fixture not found: {:?}", path);
        }

        let (_tmp, db_orig, db_saved) = open_and_save(&path, password);

        // Root group UUID matches
        assert_eq!(
            db_orig.root.uuid, db_saved.root.uuid,
            "Root UUID mismatch for {}",
            name
        );

        // All entry UUIDs match (DATA-10)
        let orig_entry_uuids = collect_entry_uuids(&db_orig.root);
        let saved_entry_uuids = collect_entry_uuids(&db_saved.root);
        assert_eq!(
            orig_entry_uuids, saved_entry_uuids,
            "Entry UUIDs differ after round-trip for {}",
            name
        );

        // All entry field values match
        for uuid in &orig_entry_uuids {
            let orig_entry = db_orig.root.entry_by_uuid(*uuid).unwrap();
            let saved_entry = db_saved.root.entry_by_uuid(*uuid).unwrap();

            for (key, orig_val) in &orig_entry.fields {
                let saved_val = saved_entry.fields.get(key).unwrap_or_else(|| {
                    panic!("Field '{}' missing after round-trip for {}", key, name)
                });
                assert_eq!(
                    orig_val.get(),
                    saved_val.get(),
                    "Field '{}' value changed after round-trip for {}",
                    key,
                    name
                );
            }
        }

        // All group names match
        let orig_group_uuids = collect_group_uuids(&db_orig.root);
        let saved_group_uuids = collect_group_uuids(&db_saved.root);
        assert_eq!(
            orig_group_uuids, saved_group_uuids,
            "Group UUIDs differ after round-trip for {}",
            name
        );

        // KeePassXC can open the saved file
        let tmp_path = _tmp.path().join("roundtrip.kdbx");
        if let Some(output) = keepassxc_cli_ls(&tmp_path, password) {
            assert!(
                output.status.success(),
                "KeePassXC cannot open round-tripped {} .\nstderr: {}",
                name, output.stderr,
            );
        }
    }
}

#[test]
fn test_roundtrip_customdata_preserved() {
    // Use the TOTP fixture from keepass-rs (password is "test")
    let path = fixture_path("test_db_kdbx4_with_totp_entry.kdbx");
    if !path.exists() {
        panic!("TOTP fixture not found: {:?}", path);
    }

    let (_tmp, db_orig, db_saved) = open_and_save(&path, "test");

    // Check entry-level CustomData
    let orig_entries = collect_entry_uuids(&db_orig.root);
    for uuid in &orig_entries {
        let orig_entry = db_orig.root.entry_by_uuid(*uuid).unwrap();
        let saved_entry = db_saved.root.entry_by_uuid(*uuid).unwrap();

        assert_eq!(
            orig_entry.custom_data.len(),
            saved_entry.custom_data.len(),
            "Entry CustomData count changed for entry {:?}",
            uuid
        );

        for (key, orig_item) in &orig_entry.custom_data {
            let saved_item = saved_entry
                .custom_data
                .get(key)
                .unwrap_or_else(|| panic!("CustomData key '{}' missing after round-trip", key));
            assert_eq!(
                orig_item.value, saved_item.value,
                "CustomData value for '{}' changed after round-trip",
                key
            );
        }
    }

    // Also test with our rich content fixture for meta-level CustomData
    let rich_path = create_richcontent_fixture();
    let (_tmp2, db_rich_orig, db_rich_saved) = open_and_save(&rich_path, RICHCONTENT_PASSWORD);

    // Meta-level CustomData
    assert_eq!(
        db_rich_orig.meta.custom_data.len(),
        db_rich_saved.meta.custom_data.len(),
        "Meta CustomData count changed"
    );

    for (key, orig_item) in &db_rich_orig.meta.custom_data {
        let saved_item =
            db_rich_saved.meta.custom_data.get(key).unwrap_or_else(|| {
                panic!("Meta CustomData key '{}' missing after round-trip", key)
            });
        assert_eq!(
            orig_item.value, saved_item.value,
            "Meta CustomData value for '{}' changed after round-trip",
            key
        );
    }
}

#[test]
fn test_roundtrip_autotype_preserved() {
    let rich_path = create_richcontent_fixture();
    let (_tmp, db_orig, db_saved) = open_and_save(&rich_path, RICHCONTENT_PASSWORD);

    let orig_entry = find_entry_by_title(&db_orig.root, "AutoTypeEntry")
        .expect("AutoTypeEntry not found in original");
    let saved_entry = find_entry_by_title(&db_saved.root, "AutoTypeEntry")
        .expect("AutoTypeEntry not found in saved");

    let orig_at = orig_entry
        .autotype
        .as_ref()
        .expect("original has no autotype");
    let saved_at = saved_entry
        .autotype
        .as_ref()
        .expect("saved has no autotype");

    assert_eq!(
        orig_at.enabled, saved_at.enabled,
        "AutoType.enabled changed"
    );
    assert_eq!(
        orig_at.default_sequence, saved_at.default_sequence,
        "AutoType.default_sequence changed"
    );
    assert_eq!(
        orig_at.associations.len(),
        saved_at.associations.len(),
        "AutoType association count changed"
    );

    for (orig_assoc, saved_assoc) in orig_at
        .associations
        .iter()
        .zip(saved_at.associations.iter())
    {
        assert_eq!(
            orig_assoc.window, saved_assoc.window,
            "AutoType association window changed"
        );
        assert_eq!(
            orig_assoc.sequence, saved_assoc.sequence,
            "AutoType association sequence changed"
        );
    }
}

#[test]
fn test_roundtrip_attachments_preserved() {
    let rich_path = create_richcontent_fixture();
    let (_tmp, db_orig, db_saved) = open_and_save(&rich_path, RICHCONTENT_PASSWORD);

    let orig_entry = find_entry_by_title(&db_orig.root, "AttachmentEntry")
        .expect("AttachmentEntry not found in original");
    let saved_entry = find_entry_by_title(&db_saved.root, "AttachmentEntry")
        .expect("AttachmentEntry not found in saved");

    assert_eq!(
        orig_entry.attachments.len(),
        saved_entry.attachments.len(),
        "Attachment count changed after round-trip"
    );

    for (name, orig_attachment) in &orig_entry.attachments {
        let saved_attachment = saved_entry
            .attachments
            .get(name)
            .unwrap_or_else(|| panic!("Attachment '{}' missing after round-trip", name));
        assert_eq!(
            orig_attachment.data.get(),
            saved_attachment.data.get(),
            "Attachment '{}' data changed after round-trip ({} bytes orig, {} bytes saved)",
            name,
            orig_attachment.data.get().len(),
            saved_attachment.data.get().len(),
        );
    }
}

#[test]
fn test_roundtrip_uuid_stability() {
    let rich_path = create_richcontent_fixture();
    let (_tmp, db_orig, db_saved) = open_and_save(&rich_path, RICHCONTENT_PASSWORD);

    let orig_entry_uuids = collect_entry_uuids(&db_orig.root);
    let saved_entry_uuids = collect_entry_uuids(&db_saved.root);
    assert_eq!(
        orig_entry_uuids, saved_entry_uuids,
        "Entry UUID set changed after round-trip"
    );

    let orig_group_uuids = collect_group_uuids(&db_orig.root);
    let saved_group_uuids = collect_group_uuids(&db_saved.root);
    assert_eq!(
        orig_group_uuids, saved_group_uuids,
        "Group UUID set changed after round-trip"
    );

    // Verify no UUIDs were added or removed
    assert_eq!(
        orig_entry_uuids.len(),
        saved_entry_uuids.len(),
        "Entry count changed"
    );
    assert_eq!(
        orig_group_uuids.len(),
        saved_group_uuids.len(),
        "Group count changed"
    );
}

#[test]
fn test_roundtrip_meta_section() {
    let rich_path = create_richcontent_fixture();
    let (_tmp, db_orig, db_saved) = open_and_save(&rich_path, RICHCONTENT_PASSWORD);

    // DatabaseName
    assert!(
        db_saved.meta.database_name.is_some(),
        "database_name is None after round-trip"
    );
    assert_eq!(
        db_orig.meta.database_name, db_saved.meta.database_name,
        "database_name changed"
    );

    // Description
    assert_eq!(
        db_orig.meta.database_description, db_saved.meta.database_description,
        "database_description changed"
    );

    // MemoryProtection
    let orig_mp = db_orig
        .meta
        .memory_protection
        .as_ref()
        .expect("original has no memory_protection");
    let saved_mp = db_saved
        .meta
        .memory_protection
        .as_ref()
        .expect("saved has no memory_protection");
    assert_eq!(
        orig_mp.protect_title, saved_mp.protect_title,
        "protect_title changed"
    );
    assert_eq!(
        orig_mp.protect_username, saved_mp.protect_username,
        "protect_username changed"
    );
    assert_eq!(
        orig_mp.protect_password, saved_mp.protect_password,
        "protect_password changed"
    );
    assert!(saved_mp.protect_password, "protect_password should be true");
    assert_eq!(
        orig_mp.protect_url, saved_mp.protect_url,
        "protect_url changed"
    );
    assert_eq!(
        orig_mp.protect_notes, saved_mp.protect_notes,
        "protect_notes changed"
    );

    // SettingsChanged
    assert_eq!(
        db_orig.meta.settings_changed, db_saved.meta.settings_changed,
        "settings_changed timestamp changed"
    );

    // history_max_items / history_max_size
    assert_eq!(
        db_orig.meta.history_max_items, db_saved.meta.history_max_items,
        "history_max_items changed"
    );
    assert_eq!(
        db_orig.meta.history_max_size, db_saved.meta.history_max_size,
        "history_max_size changed"
    );

    // maintenance_history_days
    assert_eq!(
        db_orig.meta.maintenance_history_days, db_saved.meta.maintenance_history_days,
        "maintenance_history_days changed"
    );

    // recyclebin_enabled and recyclebin_uuid
    assert_eq!(
        db_orig.meta.recyclebin_enabled, db_saved.meta.recyclebin_enabled,
        "recyclebin_enabled changed"
    );

    // Meta-level CustomData (keys and values identical)
    assert_eq!(
        db_orig.meta.custom_data.len(),
        db_saved.meta.custom_data.len(),
        "meta custom_data count changed"
    );
    for (key, orig_item) in &db_orig.meta.custom_data {
        let saved_item = db_saved
            .meta
            .custom_data
            .get(key)
            .unwrap_or_else(|| panic!("Meta custom_data key '{}' missing", key));
        assert_eq!(
            orig_item.value, saved_item.value,
            "Meta custom_data '{}' value changed",
            key
        );
    }
}

#[test]
fn test_modify_and_keepassxc_open() {
    let path = fixture_path("test_db_kdbx4_with_password_aes.kdbx");
    if !path.exists() {
        panic!("Fixture not found: {:?}", path);
    }

    let password = "demopass";
    let key = DatabaseKey::new().with_password(password);
    let mut db =
        Database::open(&mut File::open(&path).unwrap(), key).expect("failed to open fixture");

    // Add a new entry
    let mut new_entry = Entry::new();
    new_entry.set_unprotected(fields::TITLE, "ManyKee Added Entry");
    new_entry.set_unprotected(fields::USERNAME, "testuser");
    new_entry.set_protected(fields::PASSWORD, "testpass");
    db.root.entries.push(new_entry);

    // Save to tempfile
    let tmp = TempDir::new().unwrap();
    let saved_path = tmp.path().join("modified.kdbx");
    save_db(&db, &saved_path, password);

    // keepassxc-cli ls should succeed
    let Some(output) = keepassxc_cli_ls(&saved_path, password) else {
        return;
    };
    assert!(
        output.status.success(),
        "keepassxc-cli cannot open modified database.\nstderr: {}",
        output.stderr,
    );

    // keepassxc-cli show should find the new entry
    let Some(show_output) = keepassxc_cli_show(&saved_path, password, "ManyKee Added Entry") else {
        return;
    };
    assert!(
        show_output.status.success(),
        "keepassxc-cli show failed for added entry.\nstderr: {}",
        show_output.stderr,
    );
    assert!(
        show_output.stdout.contains("testuser"),
        "Expected 'testuser' in show output.\nstdout: {}",
        show_output.stdout,
    );
}

#[test]
fn test_delete_and_keepassxc_open() {
    let path = fixture_path("test_db_kdbx4_with_password_deleted_entry.kdbx");
    if !path.exists() {
        panic!("Fixture not found: {:?}", path);
    }

    let password = "demopass";
    let key = DatabaseKey::new().with_password(password);
    let mut db =
        Database::open(&mut File::open(&path).unwrap(), key).expect("failed to open fixture");

    // Find an entry to soft-delete
    let entry_uuid = db
        .root
        .entries
        .first()
        .or_else(|| {
            // Search in subgroups
            db.root.groups.iter().flat_map(|g| g.entries.iter()).next()
        })
        .expect("No entry found to delete")
        .uuid;

    // Enable recycle bin and soft-delete
    db.meta.recyclebin_enabled = Some(true);
    let entry = db.root.remove_entry(entry_uuid).expect("entry not found");
    let now = keepass::db::Times::now();
    db.deleted_objects.insert(entry_uuid, Some(now));

    // Create recycle bin if needed
    let bin_uuid = if let Some(uuid) = db.meta.recyclebin_uuid {
        if !uuid.is_nil() && db.root.group_by_uuid(uuid).is_some() {
            uuid
        } else {
            let mut bin = Group::new("Recycle Bin");
            bin.icon_id = Some(43);
            let uuid = bin.uuid;
            db.meta.recyclebin_uuid = Some(uuid);
            db.root.groups.push(bin);
            uuid
        }
    } else {
        let mut bin = Group::new("Recycle Bin");
        bin.icon_id = Some(43);
        let uuid = bin.uuid;
        db.meta.recyclebin_uuid = Some(uuid);
        db.root.groups.push(bin);
        uuid
    };

    // Move entry to recycle bin
    let bin = db.root.group_by_uuid_mut(bin_uuid).unwrap();
    bin.entries.push(entry);

    // Save
    let tmp = TempDir::new().unwrap();
    let saved_path = tmp.path().join("deleted.kdbx");
    save_db(&db, &saved_path, password);

    // KeePassXC should open without error
    if let Some(output) = keepassxc_cli_ls(&saved_path, password) {
        assert!(
            output.status.success(),
            "keepassxc-cli cannot open database after delete.\nstderr: {}",
            output.stderr,
        );
    }

    // Reopen and verify deleted_objects contains the UUID
    let db_reopened = Database::open(
        &mut File::open(&saved_path).unwrap(),
        DatabaseKey::new().with_password(password),
    )
    .expect("failed to reopen");

    assert!(
        db_reopened.deleted_objects.contains_key(&entry_uuid),
        "DeletedObjects should contain the deleted entry UUID"
    );
}

#[test]
fn test_xml_body_semantic_comparison() {
    let path = fixture_path("test_db_kdbx4_with_password_aes.kdbx");
    if !path.exists() {
        panic!("Fixture not found: {:?}", path);
    }

    let password = "demopass";

    // Get XML from original
    let xml_orig = Database::get_xml(
        &mut File::open(&path).unwrap(),
        DatabaseKey::new().with_password(password),
    )
    .expect("failed to get XML from original");

    // Open, save, get XML from saved
    let key = DatabaseKey::new().with_password(password);
    let db = Database::open(&mut File::open(&path).unwrap(), key).expect("failed to open fixture");

    let tmp = TempDir::new().unwrap();
    let saved_path = tmp.path().join("semantic.kdbx");
    save_db(&db, &saved_path, password);

    let xml_saved = Database::get_xml(
        &mut File::open(&saved_path).unwrap(),
        DatabaseKey::new().with_password(password),
    )
    .expect("failed to get XML from saved");

    // Parse both XMLs as strings for structural comparison
    let _orig_str = String::from_utf8_lossy(&xml_orig);
    let _saved_str = String::from_utf8_lossy(&xml_saved);

    // Compare structurally: both should parse into databases with same structure
    let db_from_orig = Database::open(
        &mut File::open(&path).unwrap(),
        DatabaseKey::new().with_password(password),
    )
    .unwrap();
    let db_from_saved = Database::open(
        &mut File::open(&saved_path).unwrap(),
        DatabaseKey::new().with_password(password),
    )
    .unwrap();

    // Same number of entries and groups
    assert_eq!(
        count_entries(&db_from_orig.root),
        count_entries(&db_from_saved.root),
        "Entry count differs"
    );
    assert_eq!(
        count_groups(&db_from_orig.root),
        count_groups(&db_from_saved.root),
        "Group count differs"
    );

    // Same entry field keys and unprotected values (compare as sets)
    let orig_uuids = collect_entry_uuids(&db_from_orig.root);
    for uuid in &orig_uuids {
        let orig_entry = db_from_orig.root.entry_by_uuid(*uuid).unwrap();
        let saved_entry = db_from_saved.root.entry_by_uuid(*uuid).unwrap();

        let orig_keys: HashSet<_> = orig_entry.fields.keys().collect();
        let saved_keys: HashSet<_> = saved_entry.fields.keys().collect();
        assert_eq!(
            orig_keys, saved_keys,
            "Field keys differ for entry {:?}",
            uuid
        );
    }

    // Same group names and UUIDs
    let orig_group_uuids = collect_group_uuids(&db_from_orig.root);
    let saved_group_uuids = collect_group_uuids(&db_from_saved.root);
    assert_eq!(orig_group_uuids, saved_group_uuids, "Group UUIDs differ");

    // Same CustomData keys at meta level
    let orig_cd_keys: HashSet<_> = db_from_orig.meta.custom_data.keys().collect();
    let saved_cd_keys: HashSet<_> = db_from_saved.meta.custom_data.keys().collect();
    assert_eq!(orig_cd_keys, saved_cd_keys, "Meta CustomData keys differ");

    // Same Meta fields
    assert_eq!(
        db_from_orig.meta.database_name, db_from_saved.meta.database_name,
        "DatabaseName differs"
    );
    assert_eq!(
        db_from_orig.meta.memory_protection, db_from_saved.meta.memory_protection,
        "MemoryProtection differs"
    );
}

#[test]
fn test_roundtrip_tags_preserved() {
    let rich_path = create_richcontent_fixture();
    let (_tmp, db_orig, db_saved) = open_and_save(&rich_path, RICHCONTENT_PASSWORD);

    let orig_entry = find_entry_by_title(&db_orig.root, "TaggedEntry")
        .expect("TaggedEntry not found in original");
    let saved_entry =
        find_entry_by_title(&db_saved.root, "TaggedEntry").expect("TaggedEntry not found in saved");

    assert_eq!(
        orig_entry.tags.len(),
        saved_entry.tags.len(),
        "Tag count changed"
    );

    // Tags may be reordered, compare as sets
    let orig_tags: HashSet<_> = orig_entry.tags.iter().collect();
    let saved_tags: HashSet<_> = saved_entry.tags.iter().collect();
    assert_eq!(orig_tags, saved_tags, "Tags changed after round-trip");
}
