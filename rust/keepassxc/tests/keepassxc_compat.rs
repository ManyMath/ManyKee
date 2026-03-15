//! KeePassXC cross-open compatibility tests.
//!
//! These tests validate write-side crypto by creating KDBX 4.x databases
//! using keepass-rs `save_kdbx4` and verifying that `keepassxc-cli` can
//! open, list, and show entries from them.
//!
//! Requirements covered:
//!: Fresh random MainSeed and EncryptionIV on every save
//!: Valid HMAC block stream and header HMAC
//!: Protected values encrypted with inner random stream

mod common;

use std::ffi::OsString;
use std::fs::File;
use std::path::Path;

use common::official_tools::{
    discover_keepassxc, mode_from_env, run_keepassxc_with_stdin_lines, OfficialTool,
    RedactedOutput, REQUIRED_KEEPASSXC_VERSION,
};
use keepass::db::{fields, Database, Entry, Group};
use keepass::DatabaseKey;
use tempfile::TempDir;

#[test]
fn official_tool_calls_use_shared_helper_policy() {
    let source_path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/keepassxc_compat.rs");
    let source = std::fs::read_to_string(source_path).expect("failed to read test source");
    let direct_command = ["Command::new(", "\"keepassxc-cli\"", ")"].concat();
    let direct_stdio = ["Stdio", "::", "piped"].concat();
    let shared_module = ["mod ", "common;"].concat();
    let shared_runner = ["run_keepassxc", "_with_stdin_lines"].concat();

    assert!(
        source.contains(&shared_module),
        "KeePassXC compatibility tests must import shared test helpers"
    );
    assert!(
        source.contains(&shared_runner),
        "KeePassXC compatibility tests must use shared official-tool runner"
    );
    assert!(
        !source.contains(&direct_command),
        "KeePassXC compatibility tests must not spawn keepassxc-cli directly"
    );
    assert!(
        !source.contains(&direct_stdio),
        "KeePassXC compatibility tests must not manage official-tool stdio directly"
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

/// Run `keepassxc-cli ls <db_path>` and return redacted process output.
fn keepassxc_cli_ls(db_path: &Path, password: &str) -> Option<RedactedOutput> {
    let tool = keepassxc_tool_or_skip()?;
    let args = vec![OsString::from("ls"), db_path.as_os_str().to_os_string()];

    Some(
        run_keepassxc_with_stdin_lines(&tool, &args, &[password], &[password])
            .unwrap_or_else(|err| panic!("{err}")),
    )
}

/// Run `keepassxc-cli show <db_path> <entry>` and return redacted process output.
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

/// Create a simple test database with one group and one entry.
fn create_test_db() -> Database {
    let mut db = Database::new(Default::default());
    db.meta.database_name = Some("KeePassXC Compat Test".to_string());

    let mut group = Group::new("TestGroup");
    let mut entry = Entry::new();
    entry.set_unprotected(fields::TITLE, "TestEntry");
    entry.set_unprotected(fields::USERNAME, "testuser");
    entry.set_protected(fields::PASSWORD, "testpass123");
    group.entries.push(entry);
    db.root.groups.push(group);

    db
}

/// Save a database to a file path.
fn save_db(db: &Database, path: &Path, password: &str) {
    let mut file = File::create(path).expect("failed to create db file");
    let key = DatabaseKey::new().with_password(password);
    db.save(&mut file, key).expect("failed to save database");
}

/// Write and verify keepassxc-cli can list entries.
#[test]
fn write_db_keepassxc_can_ls() {
    let tmp = TempDir::new().unwrap();
    let db_path = tmp.path().join("test_write.kdbx");
    let password = "test_write_password";

    let db = create_test_db();
    save_db(&db, &db_path, password);

    let Some(output) = keepassxc_cli_ls(&db_path, password) else {
        return;
    };

    assert!(
        output.status.success(),
        "keepassxc-cli ls failed (exit={:?}).\nstdout: {}\nstderr: {}",
        output.status.code(),
        output.stdout,
        output.stderr,
    );

    // The listing should contain our group or entry name
    assert!(
        output.stdout.contains("TestGroup") || output.stdout.contains("TestEntry"),
        "Expected TestGroup or TestEntry in keepassxc-cli ls output.\nstdout: {}",
        output.stdout,
    );
}

/// Write and verify keepassxc-cli can show entry fields.
#[test]
fn write_db_keepassxc_show_entry_fields() {
    let tmp = TempDir::new().unwrap();
    let db_path = tmp.path().join("test_show.kdbx");
    let password = "test_show_password";

    let db = create_test_db();
    save_db(&db, &db_path, password);

    let Some(output) = keepassxc_cli_show(&db_path, password, "TestGroup/TestEntry") else {
        return;
    };

    assert!(
        output.status.success(),
        "keepassxc-cli show failed (exit={:?}).\nstdout: {}\nstderr: {}",
        output.status.code(),
        output.stdout,
        output.stderr,
    );

    assert!(
        output.stdout.contains("testuser"),
        "Expected 'testuser' in keepassxc-cli show output.\nstdout: {}",
        output.stdout,
    );
}

/// Round-trip preserves entries and is readable by keepassxc-cli.
#[test]
fn roundtrip_preserves_entries() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../keepass-rs/tests/resources/test_db_kdbx4_with_password_aes.kdbx");

    if !fixture.exists() {
        panic!(
            "Fixture database not found at {:?}. \
 Ensure keepass-rs test resources are available.",
            fixture
        );
    }

    let password = "demopass";
    let key = DatabaseKey::new().with_password(password);

    // Open fixture
    let db = Database::open(&mut File::open(&fixture).unwrap(), key.clone())
        .expect("failed to open fixture db");

    let original_entry_count = count_entries(&db.root);
    let original_group_count = count_groups(&db.root);
    assert!(original_entry_count > 0, "Fixture db should have entries");

    // Save to new file
    let tmp = TempDir::new().unwrap();
    let resaved_path = tmp.path().join("resaved.kdbx");
    save_db(&db, &resaved_path, password);

    // Re-open with keepass-rs
    let db2 = Database::open(
        &mut File::open(&resaved_path).unwrap(),
        DatabaseKey::new().with_password(password),
    )
    .expect("failed to re-open saved db");

    assert_eq!(
        count_entries(&db2.root),
        original_entry_count,
        "Entry count changed after round-trip"
    );
    assert_eq!(
        count_groups(&db2.root),
        original_group_count,
        "Group count changed after round-trip"
    );

    // Verify keepassxc-cli can also open the re-saved file
    let Some(output) = keepassxc_cli_ls(&resaved_path, password) else {
        return;
    };
    assert!(
        output.status.success(),
        "keepassxc-cli cannot open re-saved database.\nstderr: {}",
        output.stderr,
    );
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

/// Verify fresh random material (MainSeed + IV) on each save.
#[test]
fn fresh_random_material_per_save() {
    let tmp = TempDir::new().unwrap();
    let path1 = tmp.path().join("save1.kdbx");
    let path2 = tmp.path().join("save2.kdbx");
    let password = "test_fresh_random";

    let db = create_test_db();
    save_db(&db, &path1, password);
    save_db(&db, &path2, password);

    let bytes1 = std::fs::read(&path1).unwrap();
    let bytes2 = std::fs::read(&path2).unwrap();

    assert_ne!(
        bytes1, bytes2,
        "Two saves of the same database produced identical bytes: \
 MainSeed/IV are not being regenerated ( violation)"
    );

    // Both files should still be openable
    let key = DatabaseKey::new().with_password(password);
    Database::open(&mut bytes1.as_slice(), key.clone()).expect("First save is not openable");
    Database::open(&mut bytes2.as_slice(), key).expect("Second save is not openable");
}

/// ChaCha20 round-trip is readable by keepassxc-cli.
#[test]
fn chacha20_roundtrip_keepassxc_compat() {
    let fixture = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../keepass-rs/tests/resources/test_db_kdbx4_with_password_argon2id_chacha20.kdbx");

    if !fixture.exists() {
        panic!(
            "ChaCha20 fixture not found at {:?}. \
 Ensure keepass-rs test resources are available.",
            fixture
        );
    }

    let password = "demopass";
    let key = DatabaseKey::new().with_password(password);

    let db = Database::open(&mut File::open(&fixture).unwrap(), key.clone())
        .expect("failed to open chacha20 fixture");

    let tmp = TempDir::new().unwrap();
    let resaved = tmp.path().join("chacha20_resaved.kdbx");
    save_db(&db, &resaved, password);

    // keepassxc-cli must accept the re-saved ChaCha20 database
    let Some(output) = keepassxc_cli_ls(&resaved, password) else {
        return;
    };
    assert!(
        output.status.success(),
        "keepassxc-cli cannot open ChaCha20 re-saved database.\nstderr: {}",
        output.stderr,
    );

    // Also verify keepass-rs can re-open it
    Database::open(
        &mut File::open(&resaved).unwrap(),
        DatabaseKey::new().with_password(password),
    )
    .expect("keepass-rs cannot re-open the ChaCha20 saved database");
}
