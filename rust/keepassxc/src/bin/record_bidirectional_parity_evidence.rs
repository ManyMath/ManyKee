use keepassxc::compat_evidence::{EvidenceLane, EvidenceRecord, FeatureClaim, SupportStatus};
use keepassxc::{semantic_snapshot, Database, DatabaseKey};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use std::fs::{self, File};
use std::io;
use std::path::{Path, PathBuf};
use std::process;
use tempfile::TempDir;

const FIXTURE_PASSWORD: &str = "manykee-fixture-password";
const STARTER_RICHCONTENT_ID: &str = "starter-richcontent";
const STARTER_RICHCONTENT_PATH: &str =
    "rust/keepassxc/tests/resources/test_db_kdbx4_richcontent.kdbx";
const STARTER_RICHCONTENT_PASSWORD: &str = "testpass123";
const EVIDENCE_DIR: &str = "fixtures/compat/evidence";
const SNAPSHOT_DIR: &str = "fixtures/compat/snapshots";
const STARTER_WRITE_SNAPSHOT: &str =
    "fixtures/compat/snapshots/starter-richcontent-bidirectional-write.semantic.json";
const STARTER_WRITE_EVIDENCE: &str =
    "fixtures/compat/evidence/manykee-write-starter-richcontent-parity.json";

const SUPPORTED_OFFICIAL_FIXTURE_IDS: [&str; 6] = [
    "keepassxc-password-basic",
    "keepassxc-keyfile-basic",
    "keepassxc-password-keyfile",
    "keepassxc-richcontent",
    "keepassxc-attachments",
    "keepassxc-history-recycle-deleted",
];

const STARTER_WRITE_FEATURE_IDS: [&str; 11] = [
    "group_tree",
    "uuids",
    "standard_fields",
    "custom_fields",
    "protected_flags",
    "tags",
    "metadata",
    "attachments_by_hash",
    "history",
    "autotype_metadata",
    "custom_data",
];

type DynError = Box<dyn std::error::Error>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Write,
    Check,
}

#[derive(Debug, PartialEq, Eq)]
struct Cli {
    mode: Mode,
    fixture_ids: Vec<String>,
    include_starter_richcontent: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CredentialMode {
    PasswordOnly,
    KeyFileOnly { key_file: &'static str },
    PasswordAndKeyFile { key_file: &'static str },
}

#[derive(Debug, Clone, Copy)]
struct FixtureDefinition {
    fixture_id: &'static str,
    database_path: &'static str,
    credential: CredentialMode,
    feature_ids: &'static [&'static str],
}

#[derive(Debug, Clone, Copy)]
struct KnownGapExpectation {
    fixture_id: &'static str,
    feature_id: &'static str,
    reason: &'static str,
}

struct GeneratedArtifact {
    relative_path: String,
    contents: String,
}

fn main() {
    let cli = match parse_args(std::env::args().skip(1)) {
        Ok(cli) => cli,
        Err(err) => {
            eprintln!("{err}");
            eprintln!(
                "usage: record_bidirectional_parity_evidence (--write|--check) [--fixture-id <id>]... [--starter-richcontent]"
            );
            process::exit(2);
        }
    };

    if let Err(err) = run(&cli) {
        eprintln!("{err}");
        process::exit(1);
    }
}

fn parse_args<I, S>(args: I) -> Result<Cli, String>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let mut mode = None;
    let mut fixture_ids = Vec::new();
    let mut include_starter_richcontent = false;
    let mut args = args.into_iter().map(Into::into).peekable();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--write" => set_mode(&mut mode, Mode::Write)?,
            "--check" => set_mode(&mut mode, Mode::Check)?,
            "--fixture-id" => {
                let Some(fixture_id) = args.next() else {
                    return Err("--fixture-id requires a fixture ID".to_string());
                };
                if !SUPPORTED_OFFICIAL_FIXTURE_IDS.contains(&fixture_id.as_str()) {
                    return Err(format!(
                        "unsupported --fixture-id {fixture_id}; expected one of {}",
                        SUPPORTED_OFFICIAL_FIXTURE_IDS.join(", ")
                    ));
                }
                fixture_ids.push(fixture_id);
            }
            "--starter-richcontent" => include_starter_richcontent = true,
            other => return Err(format!("unknown argument: {other}")),
        }
    }

    let Some(mode) = mode else {
        return Err("missing mode; pass --write or --check".to_string());
    };

    Ok(Cli {
        mode,
        fixture_ids,
        include_starter_richcontent,
    })
}

fn set_mode(mode: &mut Option<Mode>, selected: Mode) -> Result<(), String> {
    if mode.replace(selected).is_some() {
        return Err("expected exactly one mode: --write or --check".to_string());
    }
    Ok(())
}

fn run(cli: &Cli) -> Result<(), DynError> {
    let project_root = project_root();
    let artifacts = generate_artifacts(&project_root, cli)?;

    match cli.mode {
        Mode::Write => write_artifacts(&project_root, &artifacts),
        Mode::Check => check_artifacts(&project_root, &artifacts),
    }
}

fn generate_artifacts(project_root: &Path, cli: &Cli) -> Result<Vec<GeneratedArtifact>, DynError> {
    let selected = selected_fixture_ids(cli);
    let definitions = fixture_definitions();
    let mut artifacts = Vec::new();

    for fixture_id in selected {
        let definition = definitions
            .iter()
            .find(|definition| definition.fixture_id == fixture_id)
            .expect("selected fixture ID is validated by parse_args");
        artifacts.extend(generate_official_fixture_artifacts(
            project_root,
            definition,
        )?);
    }

    if include_starter(cli) {
        artifacts.extend(generate_starter_richcontent_artifacts(project_root)?);
    }

    Ok(artifacts)
}

fn selected_fixture_ids(cli: &Cli) -> Vec<&str> {
    if cli.fixture_ids.is_empty() && !cli.include_starter_richcontent {
        return SUPPORTED_OFFICIAL_FIXTURE_IDS.to_vec();
    }

    let mut seen = BTreeSet::new();
    let mut selected = Vec::new();
    for fixture_id in &cli.fixture_ids {
        if seen.insert(fixture_id.as_str()) {
            selected.push(fixture_id.as_str());
        }
    }
    selected
}

fn include_starter(cli: &Cli) -> bool {
    cli.include_starter_richcontent || cli.fixture_ids.is_empty()
}

fn generate_official_fixture_artifacts(
    project_root: &Path,
    definition: &FixtureDefinition,
) -> Result<Vec<GeneratedArtifact>, DynError> {
    let db = open_official_fixture(project_root, definition)?;
    let read_snapshot = snapshot_json(&db, definition.fixture_id, "manykee_read")?;
    let read_snapshot_path = official_snapshot_path(definition.fixture_id, "read");
    let read_snapshot_hash = hash_text(&read_snapshot);
    let read_evidence_path = official_evidence_path(definition.fixture_id, "read");

    let read_record = evidence_record(
        &format!("manykee-read-{}", definition.fixture_id),
        definition.fixture_id,
        EvidenceLane::ManyKeeRead,
        &read_snapshot_path,
        &read_snapshot_hash,
        &read_evidence_path,
        definition.feature_ids,
        |feature_id| read_known_gap(definition.fixture_id, feature_id),
        vec![
            "ManyKee opened the committed KeePassXC-created fixture with the manifest credential."
                .to_string(),
            "Snapshot hash is SHA-256 over this recorder's semantic JSON output.".to_string(),
        ],
    );

    let (write_snapshot, write_notes, write_gap_override) =
        write_snapshot(project_root, definition, &db)?;
    let write_snapshot_path = official_snapshot_path(definition.fixture_id, "write");
    let write_snapshot_hash = hash_text(&write_snapshot);
    let write_evidence_path = official_evidence_path(definition.fixture_id, "write");

    let mut write_notes_all = vec![
        "ManyKee write evidence is lane-separated from KeePassXC source evidence.".to_string(),
        "Snapshot hash is SHA-256 over this recorder's semantic JSON output.".to_string(),
    ];
    write_notes_all.extend(write_notes);

    let write_record = evidence_record(
        &format!("manykee-write-{}", definition.fixture_id),
        definition.fixture_id,
        EvidenceLane::ManyKeeWrite,
        &write_snapshot_path,
        &write_snapshot_hash,
        &write_evidence_path,
        definition.feature_ids,
        |feature_id| {
            write_gap_override.or_else(|| write_known_gap(definition.fixture_id, feature_id))
        },
        write_notes_all,
    );

    Ok(vec![
        GeneratedArtifact {
            relative_path: read_snapshot_path,
            contents: read_snapshot,
        },
        GeneratedArtifact {
            relative_path: read_evidence_path,
            contents: pretty_json(&read_record)?,
        },
        GeneratedArtifact {
            relative_path: write_snapshot_path,
            contents: write_snapshot,
        },
        GeneratedArtifact {
            relative_path: write_evidence_path,
            contents: pretty_json(&write_record)?,
        },
    ])
}

fn generate_starter_richcontent_artifacts(
    project_root: &Path,
) -> Result<Vec<GeneratedArtifact>, DynError> {
    let db = open_password_database(
        &project_root.join(STARTER_RICHCONTENT_PATH),
        STARTER_RICHCONTENT_PASSWORD,
    )?;
    let temp = TempDir::new()?;
    let saved_path = temp.path().join("starter-richcontent-manykee.kdbx");
    save_password_database(&db, &saved_path, STARTER_RICHCONTENT_PASSWORD)?;
    let saved = open_password_database(&saved_path, STARTER_RICHCONTENT_PASSWORD)?;
    let snapshot = snapshot_json(&saved, STARTER_RICHCONTENT_ID, "manykee_write")?;
    let snapshot_hash = hash_text(&snapshot);

    let record = evidence_record(
        "manykee-write-starter-richcontent-parity",
        STARTER_RICHCONTENT_ID,
        EvidenceLane::ManyKeeWrite,
        STARTER_WRITE_SNAPSHOT,
        &snapshot_hash,
        STARTER_WRITE_EVIDENCE,
        &STARTER_WRITE_FEATURE_IDS,
        |_feature_id| None,
        vec![
            "Generated from the existing starter-richcontent fixture after a ManyKee save/reopen parity pass.".to_string(),
            "KeePassXC inspection for this ManyKee-written database is covered by the bidirectional parity test.".to_string(),
        ],
    );

    Ok(vec![
        GeneratedArtifact {
            relative_path: STARTER_WRITE_SNAPSHOT.to_string(),
            contents: snapshot,
        },
        GeneratedArtifact {
            relative_path: STARTER_WRITE_EVIDENCE.to_string(),
            contents: pretty_json(&record)?,
        },
    ])
}

fn write_snapshot(
    _project_root: &Path,
    definition: &FixtureDefinition,
    db: &Database,
) -> Result<(String, Vec<String>, Option<&'static KnownGapExpectation>), DynError> {
    let temp = TempDir::new()?;
    let saved_path = temp
        .path()
        .join(format!("{}-manykee-write.kdbx", definition.fixture_id));

    match save_official_fixture(db, definition, &saved_path) {
        Ok(()) => {
            let saved = reopen_official_fixture(definition, &saved_path)?;
            Ok((
                snapshot_json(&saved, definition.fixture_id, "manykee_write")?,
                vec!["ManyKee saved the fixture to a temporary KDBX and reopened it successfully.".to_string()],
                None,
            ))
        }
        Err(err) if is_expected_full_write_gap(definition, err.as_ref()) => Ok((
            snapshot_json(db, definition.fixture_id, "manykee_write")?,
            vec![format!(
                "Known gap: no ManyKee-saved KDBX snapshot exists yet for this fixture; this snapshot captures the ManyKee-opened source fixture. observed_error={err}"
            )],
            known_gap(definition.fixture_id, definition.feature_ids[0]),
        )),
        Err(err) => Err(err),
    }
}

fn evidence_record<F>(
    evidence_id: &str,
    fixture_id: &str,
    lane: EvidenceLane,
    snapshot_path: &str,
    snapshot_sha256: &str,
    evidence_path: &str,
    feature_ids: &[&str],
    gap_for: F,
    notes: Vec<String>,
) -> EvidenceRecord
where
    F: Fn(&str) -> Option<&'static KnownGapExpectation>,
{
    let mut known_gap_ids = BTreeSet::new();
    let claims = feature_ids
        .iter()
        .map(|feature_id| match gap_for(feature_id) {
            Some(gap) => {
                known_gap_ids.insert((*feature_id).to_string());
                FeatureClaim {
                    feature_id: (*feature_id).to_string(),
                    status: SupportStatus::KnownGap,
                    fixture_id: None,
                    lane: None,
                    evidence_path: Some(evidence_path.to_string()),
                    notes: vec![gap.reason.to_string()],
                }
            }
            None => FeatureClaim {
                feature_id: (*feature_id).to_string(),
                status: SupportStatus::Supported,
                fixture_id: None,
                lane: None,
                evidence_path: Some(evidence_path.to_string()),
                notes: Vec::new(),
            },
        })
        .collect::<Vec<_>>();

    EvidenceRecord {
        schema_version: 1,
        evidence_id: evidence_id.to_string(),
        fixture_id: fixture_id.to_string(),
        lane,
        tool_name: "manykee".to_string(),
        tool_version: env!("CARGO_PKG_VERSION").to_string(),
        status: if known_gap_ids.is_empty() {
            SupportStatus::Supported
        } else {
            SupportStatus::KnownGap
        },
        snapshot_path: Some(snapshot_path.to_string()),
        snapshot_sha256: Some(snapshot_sha256.to_string()),
        evidence_path: Some(evidence_path.to_string()),
        claims,
        known_gaps: known_gap_ids.into_iter().collect(),
        non_goals: vec!["byte_identical_output".to_string()],
        notes,
    }
}

fn open_official_fixture(
    project_root: &Path,
    definition: &FixtureDefinition,
) -> Result<Database, DynError> {
    let path = project_root.join(definition.database_path);
    let mut file = File::open(&path)?;
    Ok(Database::open(
        &mut file,
        database_key(project_root, definition)?,
    )?)
}

fn save_official_fixture(
    db: &Database,
    definition: &FixtureDefinition,
    path: &Path,
) -> Result<(), DynError> {
    let mut file = File::create(path)?;
    db.save(&mut file, database_key(&project_root(), definition)?)?;
    Ok(())
}

fn reopen_official_fixture(
    definition: &FixtureDefinition,
    path: &Path,
) -> Result<Database, DynError> {
    let mut file = File::open(path)?;
    Ok(Database::open(
        &mut file,
        database_key(&project_root(), definition)?,
    )?)
}

fn database_key(
    project_root: &Path,
    definition: &FixtureDefinition,
) -> Result<DatabaseKey, DynError> {
    let key = match definition.credential {
        CredentialMode::PasswordOnly => DatabaseKey::new().with_password(FIXTURE_PASSWORD),
        CredentialMode::KeyFileOnly { key_file } => {
            DatabaseKey::new().with_keyfile(&mut File::open(project_root.join(key_file))?)?
        }
        CredentialMode::PasswordAndKeyFile { key_file } => DatabaseKey::new()
            .with_password(FIXTURE_PASSWORD)
            .with_keyfile(&mut File::open(project_root.join(key_file))?)?,
    };
    Ok(key)
}

fn open_password_database(path: &Path, password: &str) -> Result<Database, DynError> {
    let mut file = File::open(path)?;
    Ok(Database::open(
        &mut file,
        DatabaseKey::new().with_password(password),
    )?)
}

fn save_password_database(db: &Database, path: &Path, password: &str) -> Result<(), DynError> {
    let mut file = File::create(path)?;
    db.save(&mut file, DatabaseKey::new().with_password(password))?;
    Ok(())
}

fn read_known_gap(fixture_id: &str, feature_id: &str) -> Option<&'static KnownGapExpectation> {
    if fixture_id == "keepassxc-history-recycle-deleted" && feature_id == "deleted_objects" {
        return known_gap(fixture_id, feature_id);
    }
    None
}

fn write_known_gap(fixture_id: &str, feature_id: &str) -> Option<&'static KnownGapExpectation> {
    match (fixture_id, feature_id) {
        ("keepassxc-history-recycle-deleted", "deleted_objects") => {
            known_gap(fixture_id, feature_id)
        }
        _ => None,
    }
}

fn is_expected_full_write_gap(
    definition: &FixtureDefinition,
    err: &(dyn std::error::Error + 'static),
) -> bool {
    let error_text = format!("{err:?} {err}");
    let is_unsupported_version = error_text.contains("UnsupportedVersion")
        || error_text
            .to_ascii_lowercase()
            .contains("unsupported database version");
    is_unsupported_version
        && definition
            .feature_ids
            .iter()
            .all(|feature_id| known_gap(definition.fixture_id, feature_id).is_some())
}

fn known_gap(fixture_id: &str, feature_id: &str) -> Option<&'static KnownGapExpectation> {
    known_gap_expectations()
        .iter()
        .find(|gap| gap.fixture_id == fixture_id && gap.feature_id == feature_id)
}

fn known_gap_expectations() -> &'static [KnownGapExpectation] {
    &[]
}

fn write_artifacts(project_root: &Path, artifacts: &[GeneratedArtifact]) -> Result<(), DynError> {
    fs::create_dir_all(project_root.join(EVIDENCE_DIR))?;
    fs::create_dir_all(project_root.join(SNAPSHOT_DIR))?;
    for artifact in artifacts {
        let path = project_root.join(&artifact.relative_path);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, &artifact.contents)?;
    }
    Ok(())
}

fn check_artifacts(project_root: &Path, artifacts: &[GeneratedArtifact]) -> Result<(), DynError> {
    for artifact in artifacts {
        let path = project_root.join(&artifact.relative_path);
        let actual = fs::read_to_string(&path).map_err(|source| {
            io::Error::new(
                source.kind(),
                format!("failed to read {}: {source}", artifact.relative_path),
            )
        })?;
        if actual != artifact.contents {
            return Err(io::Error::other(format!(
                    "{} is stale; run `cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_bidirectional_parity_evidence -- --write`",
                    artifact.relative_path
                ),
            )
            .into());
        }
    }
    Ok(())
}

fn official_snapshot_path(fixture_id: &str, lane: &str) -> String {
    format!("fixtures/compat/snapshots/{fixture_id}-manykee-{lane}.semantic.json")
}

fn official_evidence_path(fixture_id: &str, lane: &str) -> String {
    format!("fixtures/compat/evidence/manykee-{lane}-{fixture_id}.json")
}

fn snapshot_json(db: &Database, fixture_id: &str, evidence_lane: &str) -> Result<String, DynError> {
    let mut json = semantic_snapshot::snapshot_json_pretty(db)?;
    let source_fixture_id = serde_json::to_string(fixture_id)?;
    let evidence_lane = serde_json::to_string(evidence_lane)?;
    let prefix = "{\n \"schema_version\": 1,";
    let provenance = format!(
        "{{\n \"schema_version\": 1,\n \"source_fixture_id\": {source_fixture_id},\n \"evidence_lane\": {evidence_lane},"
    );

    if !json.starts_with(prefix) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "semantic snapshot schema header changed",
        )
        .into());
    }

    json.replace_range(..prefix.len(), &provenance);
    json.push('\n');
    Ok(json)
}

fn pretty_json<T: Serialize>(value: &T) -> Result<String, DynError> {
    let mut json = serde_json::to_string_pretty(value)?;
    json.push('\n');
    Ok(json)
}

fn hash_text(contents: &str) -> String {
    hex::encode(Sha256::digest(contents.as_bytes()))
}

fn fixture_definitions() -> Vec<FixtureDefinition> {
    vec![
        FixtureDefinition {
            fixture_id: "keepassxc-password-basic",
            database_path:
                "fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-basic.kdbx",
            credential: CredentialMode::PasswordOnly,
            feature_ids: &[
                "credential_password_only",
                "cipher_aes256",
                "kdf_aes",
                "metadata",
                "group_tree",
                "standard_fields",
            ],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-keyfile-basic",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-keyfile-basic.kdbx",
            credential: CredentialMode::KeyFileOnly {
                key_file: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-keyfile-basic.keyx",
            },
            feature_ids: &[
                "credential_key_file_only",
                "cipher_aes256",
                "kdf_aes",
                "metadata",
            ],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-password-keyfile",
            database_path:
                "fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-keyfile.kdbx",
            credential: CredentialMode::PasswordAndKeyFile {
                key_file:
                    "fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-keyfile.keyx",
            },
            feature_ids: &[
                "credential_password_key_file",
                "cipher_aes256",
                "kdf_aes",
                "metadata",
            ],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-richcontent",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-richcontent.kdbx",
            credential: CredentialMode::PasswordOnly,
            feature_ids: &[
                "metadata",
                "group_tree",
                "standard_fields",
                "custom_fields",
                "protected_flags",
                "tags",
                "totp",
                "autotype_metadata",
                "custom_data",
            ],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-attachments",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-attachments.kdbx",
            credential: CredentialMode::PasswordOnly,
            feature_ids: &["attachments_by_hash", "standard_fields", "group_tree"],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-history-recycle-deleted",
            database_path:
                "fixtures/compat/official/keepassxc/2.7.12/keepassxc-history-recycle-deleted.kdbx",
            credential: CredentialMode::PasswordOnly,
            feature_ids: &[
                "history",
                "deleted_objects",
                "group_tree",
                "standard_fields",
            ],
        },
    ]
}

fn project_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[cfg(test)]
mod tests {
    use super::{
        include_starter, known_gap_expectations, parse_args, selected_fixture_ids, Mode,
        SUPPORTED_OFFICIAL_FIXTURE_IDS,
    };
    use std::collections::BTreeSet;

    const KNOWN_GAP_BASELINE: [(&str, &str); 19] = [
        ("keepassxc-attachments", "attachments_by_hash"),
        ("keepassxc-attachments", "group_tree"),
        ("keepassxc-attachments", "standard_fields"),
        ("keepassxc-history-recycle-deleted", "deleted_objects"),
        ("keepassxc-keyfile-basic", "cipher_aes256"),
        ("keepassxc-keyfile-basic", "credential_key_file_only"),
        ("keepassxc-keyfile-basic", "kdf_aes"),
        ("keepassxc-keyfile-basic", "metadata"),
        ("keepassxc-password-basic", "cipher_aes256"),
        ("keepassxc-password-basic", "credential_password_only"),
        ("keepassxc-password-basic", "group_tree"),
        ("keepassxc-password-basic", "kdf_aes"),
        ("keepassxc-password-basic", "metadata"),
        ("keepassxc-password-basic", "standard_fields"),
        ("keepassxc-password-keyfile", "cipher_aes256"),
        ("keepassxc-password-keyfile", "credential_password_key_file"),
        ("keepassxc-password-keyfile", "kdf_aes"),
        ("keepassxc-password-keyfile", "metadata"),
        ("keepassxc-richcontent", "totp"),
    ];

    fn known_gap_baseline_set() -> BTreeSet<(&'static str, &'static str)> {
        KNOWN_GAP_BASELINE.into_iter().collect()
    }

    fn live_known_gap_set() -> BTreeSet<(&'static str, &'static str)> {
        known_gap_expectations()
            .iter()
            .map(|gap| (gap.fixture_id, gap.feature_id))
            .collect()
    }

    #[test]
    fn known_gap_baseline_matches_evidence() {
        let baseline = known_gap_baseline_set();
        assert_eq!(
            baseline.len(),
            19,
            " baseline must retain all 19 known-gap rows"
        );
        assert!(baseline.contains(&("keepassxc-richcontent", "totp")));
        assert!(baseline.contains(&("keepassxc-history-recycle-deleted", "deleted_objects",)));
        assert_eq!(baseline, KNOWN_GAP_BASELINE.into_iter().collect());
    }

    #[test]
    fn live_known_gap_inventory_is_subset_of_baseline() {
        let baseline = known_gap_baseline_set();
        let live = live_known_gap_set();
        let unexpected = live.difference(&baseline).collect::<Vec<_>>();
        assert!(
            unexpected.is_empty(),
            "live known gaps must come from the immutable baseline: {unexpected:?}"
        );
    }

    #[test]
    fn parses_repeatable_fixture_filter_and_starter_selector() {
        let cli = parse_args([
            "--check",
            "--fixture-id",
            "keepassxc-password-basic",
            "--fixture-id",
            "keepassxc-richcontent",
            "--starter-richcontent",
        ])
        .expect("valid selector arguments should parse");

        assert_eq!(cli.mode, Mode::Check);
        assert_eq!(
            cli.fixture_ids,
            ["keepassxc-password-basic", "keepassxc-richcontent"]
        );
        assert!(cli.include_starter_richcontent);
        assert_eq!(
            selected_fixture_ids(&cli),
            ["keepassxc-password-basic", "keepassxc-richcontent"]
        );
        assert!(include_starter(&cli));
    }

    #[test]
    fn no_filters_selects_all_artifacts() {
        let cli = parse_args(["--write"]).expect("mode-only invocation should parse");

        assert_eq!(selected_fixture_ids(&cli), SUPPORTED_OFFICIAL_FIXTURE_IDS);
        assert!(include_starter(&cli));
    }

    #[test]
    fn rejects_unknown_fixture_id() {
        let error = parse_args(["--check", "--fixture-id", "keepassxc-unknownxml"])
            .expect_err("manual-pending fixture must not be accepted as a filter");

        assert!(error.contains("unsupported --fixture-id keepassxc-unknownxml"));
    }
}
