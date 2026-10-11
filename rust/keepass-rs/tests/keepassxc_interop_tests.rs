//! Interoperability checks against a locally installed `keepassxc-cli`.
//!
//! Round-trip tests inside this crate cannot catch a key derivation bug that
//! is symmetric between the writer and the reader, so these tests write a
//! database with this crate and read it back with an independent
//! implementation. They are skipped (and pass) when `keepassxc-cli` is not on
//! `PATH`.
#![cfg(feature = "save_kdbx4")]

use std::{
    fs::File,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

use keepass::{
    config::{
        CompressionConfig, DatabaseConfig, DatabaseVersion, InnerCipherConfig, KdfConfig, OuterCipherConfig,
    },
    db::{Database, Entry, Group, History},
    DatabaseKey,
};

const PASSWORD: &str = "demopass";
const ENTRY_TITLE: &str = "Demo Entry";
const ENTRY_PASSWORD: &str = "secret";

/// Runs `keepassxc-cli` with `args`, feeding `PASSWORD` on stdin. Returns
/// `None` when the binary is not installed.
fn keepassxc_cli(args: &[&str]) -> Option<std::process::Output> {
    let mut child = match Command::new("keepassxc-cli")
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            eprintln!("keepassxc-cli not found on PATH; skipping interop test");
            return None;
        }
        Err(e) => panic!("failed to spawn keepassxc-cli: {}", e),
    };

    child
        .stdin
        .take()
        .expect("stdin is piped")
        .write_all(format!("{}\n", PASSWORD).as_bytes())
        .expect("write password to keepassxc-cli");

    Some(child.wait_with_output().expect("wait for keepassxc-cli"))
}

struct TempFile(PathBuf);

impl TempFile {
    fn new(name: &str) -> Self {
        let mut path = std::env::temp_dir();
        path.push(format!("keepass-rs-interop-{}-{}.kdbx", std::process::id(), name));
        TempFile(path)
    }

    fn path(&self) -> &str {
        self.0.to_str().expect("temp path is UTF-8")
    }
}

impl Drop for TempFile {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

/// Asserts that keepassxc-cli opens `path` (with the password and an optional
/// key file) and decrypts the protected password of `ENTRY_TITLE` correctly.
fn assert_keepassxc_reads_protected_password(path: &str, keyfile: Option<&str>) {
    let mut args = vec!["show", "-q", "-s", "-a", "Password"];
    if let Some(keyfile) = keyfile {
        args.extend(["-k", keyfile]);
    }
    args.extend([path, ENTRY_TITLE]);

    let output = match keepassxc_cli(&args) {
        Some(output) => output,
        None => return,
    };

    assert!(
        output.status.success(),
        "keepassxc-cli failed to open the database written by this crate: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&output.stdout).trim(),
        ENTRY_PASSWORD,
        "keepassxc-cli decrypted the protected password to a different value; \
         the inner stream key derivation does not match KeePass"
    );
}

/// Writes a fresh KDBX4 database with the given inner stream cipher and
/// checks that keepassxc-cli can read its protected password.
fn assert_new_kdbx4_database_is_readable(inner_cipher_config: InnerCipherConfig, name: &str) {
    let config = DatabaseConfig {
        inner_cipher_config,
        outer_cipher_config: OuterCipherConfig::AES256,
        compression_config: CompressionConfig::GZip,
        kdf_config: KdfConfig::Aes { rounds: 10 },
        ..DatabaseConfig::default()
    };

    let mut db = Database::new(config);
    let mut root = Group::new("Root");
    let mut entry = Entry::new();
    entry.set_unprotected("Title", ENTRY_TITLE);
    entry.set_protected("Password", ENTRY_PASSWORD);
    root.entries.push(entry);
    db.root = root;

    let temp = TempFile::new(name);
    db.save(
        &mut File::create(&temp.0).expect("create temp database"),
        DatabaseKey::new().with_password(PASSWORD),
    )
    .expect("save database");

    assert_keepassxc_reads_protected_password(temp.path(), None);
}

#[test]
fn kdbx4_salsa20_inner_stream_is_readable_by_keepassxc() {
    assert_new_kdbx4_database_is_readable(InnerCipherConfig::Salsa20, "salsa20");
}

#[test]
fn kdbx4_chacha20_inner_stream_is_readable_by_keepassxc() {
    assert_new_kdbx4_database_is_readable(InnerCipherConfig::ChaCha20, "chacha20");
}

#[test]
fn kdbx3_database_resaved_as_kdbx4_is_readable_by_keepassxc() {
    // KeePassXC always writes KDBX3 with a Salsa20 inner stream. Opening such
    // a file and saving it as KDBX4 keeps that inner cipher, which is how a
    // KDBX4 + Salsa20 file arises in practice.
    let fixture = Path::new("tests/resources/test_db_kdbx3_with_hex_keyfile.kdbx");
    let keyfile = "tests/resources/test_db_kdbx3_with_hex_keyfile.key";
    let key = || {
        DatabaseKey::new()
            .with_password(PASSWORD)
            .with_keyfile(&mut File::open(keyfile).expect("open key file"))
            .expect("read key file")
    };

    let mut db = Database::open(&mut File::open(fixture).expect("open fixture"), key()).expect("open fixture");
    assert_eq!(db.config.inner_cipher_config, InnerCipherConfig::Salsa20);
    db.config.version = DatabaseVersion::KDB4(0);

    let temp = TempFile::new("kdbx3-resaved-as-kdbx4");
    db.save(&mut File::create(&temp.0).expect("create temp database"), key())
        .expect("save database as KDBX4");

    assert_keepassxc_reads_protected_password(temp.path(), Some(keyfile));
}

/// The `UserName` of each `<History>` item of the first entry with history
/// in a `keepassxc-cli export` XML document, in document order.
fn exported_history_user_names(xml: &str) -> Vec<String> {
    let start = xml.find("<History>").expect("an exported entry has history");
    let end = start + xml[start..].find("</History>").expect("history is closed");
    xml[start..end]
        .split("<Key>UserName</Key>")
        .skip(1)
        .map(|rest| {
            let rest = rest.trim_start();
            let value = rest.strip_prefix("<Value>").expect("UserName has a value");
            value[..value.find("</Value>").expect("value is closed")].to_string()
        })
        .collect()
}

#[test]
fn keepassxc_keeps_the_newest_history_items_of_a_database_written_by_this_crate() {
    // KeePass and KeePassXC store history oldest-first and drop items from
    // the front to enforce HistoryMaxItems. History written newest-first lost
    // its newest revisions the next time KeePassXC edited the entry.
    let mut db = Database::new(DatabaseConfig {
        kdf_config: KdfConfig::Aes { rounds: 10 },
        ..DatabaseConfig::default()
    });
    db.meta.history_max_items = Some(3);

    let mut entry = Entry::new();
    entry.set_unprotected("Title", ENTRY_TITLE);
    let start = entry.times.last_modification.expect("new entries have a time") - chrono::Duration::days(1);
    let mut history = History::default();
    for n in 1..=3 {
        let mut revision = entry.clone();
        revision.set_unprotected("UserName", format!("v{n}"));
        revision.times.last_modification = Some(start + chrono::Duration::hours(n));
        history.add_entry(revision);
    }
    entry.set_unprotected("UserName", "v4");
    entry.times.last_modification = Some(start + chrono::Duration::hours(4));
    entry.history = Some(history);

    let mut root = Group::new("Root");
    root.entries.push(entry);
    db.root = root;

    let temp = TempFile::new("history-order");
    db.save(
        &mut File::create(&temp.0).expect("create temp database"),
        DatabaseKey::new().with_password(PASSWORD),
    )
    .expect("save database");

    let Some(edit) = keepassxc_cli(&["edit", "-q", "-u", "v5", temp.path(), ENTRY_TITLE]) else {
        return;
    };
    assert!(
        edit.status.success(),
        "keepassxc-cli edit failed: {}",
        String::from_utf8_lossy(&edit.stderr)
    );
    let export =
        keepassxc_cli(&["export", "-q", "-f", "xml", temp.path()]).expect("keepassxc-cli is installed");
    assert!(
        export.status.success(),
        "keepassxc-cli export failed: {}",
        String::from_utf8_lossy(&export.stderr)
    );

    assert_eq!(
        exported_history_user_names(&String::from_utf8_lossy(&export.stdout)),
        ["v2", "v3", "v4"],
        "KeePassXC should have dropped only the oldest revision"
    );
}

#[cfg(feature = "save_kdbx3")]
#[test]
fn new_kdbx3_database_is_readable_by_keepassxc() {
    // KeePassXC rejects a KDBX3 hashed block stream whose terminating block
    // carries anything but an all-zero hash.
    let config = DatabaseConfig {
        version: DatabaseVersion::KDB3(1),
        inner_cipher_config: InnerCipherConfig::Salsa20,
        outer_cipher_config: OuterCipherConfig::AES256,
        compression_config: CompressionConfig::GZip,
        kdf_config: KdfConfig::Aes { rounds: 10 },
        ..DatabaseConfig::default()
    };

    let mut db = Database::new(config);
    let mut root = Group::new("Root");
    let mut entry = Entry::new();
    entry.set_unprotected("Title", ENTRY_TITLE);
    entry.set_protected("Password", ENTRY_PASSWORD);
    root.entries.push(entry);
    db.root = root;

    let temp = TempFile::new("kdbx3");
    db.save(
        &mut File::create(&temp.0).expect("create temp database"),
        DatabaseKey::new().with_password(PASSWORD),
    )
    .expect("save database");

    assert_keepassxc_reads_protected_password(temp.path(), None);
}
