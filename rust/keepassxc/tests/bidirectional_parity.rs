mod common;

use common::official_tools::{
    discover_keepassxc, mode_from_env, run_keepassxc_with_stdin_lines, OfficialTool,
    RedactedOutput, REQUIRED_KEEPASSXC_VERSION,
};
use keepassxc::compat_evidence::{
    artifact_sha256, load_evidence_dir, load_manifest, EvidenceLane, SupportStatus,
};
use keepassxc::semantic_snapshot::{
    self, AttachmentSnapshot, AutoTypeSnapshot, CustomDataSnapshot, FieldSnapshot,
    MemoryProtectionSnapshot, SemanticSnapshot,
};
use keepassxc::{fields, Database, DatabaseConfig, DatabaseKey, Entry, Group};
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::OsString;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

const FIXTURE_PASSWORD: &str = "manykee-fixture-password";
const STARTER_RICHCONTENT_PATH: &str =
    "rust/keepassxc/tests/resources/test_db_kdbx4_richcontent.kdbx";
const STARTER_RICHCONTENT_PASSWORD: &str = "testpass123";

const SUPPORTED_OFFICIAL_FIXTURE_IDS: [&str; 6] = [
    "keepassxc-password-basic",
    "keepassxc-keyfile-basic",
    "keepassxc-password-keyfile",
    "keepassxc-richcontent",
    "keepassxc-attachments",
    "keepassxc-history-recycle-deleted",
];

static BASIC_SHOW: [ShowExpectation; 1] = [ShowExpectation {
    entry_path: "Fixtures/BasicEntry",
    markers: &[
        "fixture-user",
        "https://manykee.test/basic",
        "Synthetic basic entry",
    ],
}];

static RICH_SHOW: [ShowExpectation; 3] = [
    ShowExpectation {
        entry_path: "Fixtures/Nested/CustomFieldsEntry",
        markers: &["manykee-custom-field", "custom-field-value"],
    },
    ShowExpectation {
        entry_path: "Fixtures/Nested/ProtectedEntry",
        markers: &["ProtectedEntry"],
    },
    ShowExpectation {
        entry_path: "Fixtures/Nested/TOTPEntry",
        markers: &["TOTPEntry", "totp-user"],
    },
];

static ATTACHMENT_EXPORTS: [AttachmentExpectation; 2] = [
    AttachmentExpectation {
        entry_path: "Attachments/AttachmentEntry",
        attachment_name: "sample.txt",
        source_path: "fixtures/compat/sources/keepassxc/2.7.12/attachment-text.txt",
    },
    AttachmentExpectation {
        entry_path: "Attachments/AttachmentEntry",
        attachment_name: "sample.bin",
        source_path: "fixtures/compat/sources/keepassxc/2.7.12/attachment-binary.bin",
    },
];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CredentialMode {
    PasswordOnly,
    KeyFileOnly { key_file: &'static str },
    PasswordAndKeyFile { key_file: &'static str },
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ShowExpectation {
    entry_path: &'static str,
    markers: &'static [&'static str],
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct AttachmentExpectation {
    entry_path: &'static str,
    attachment_name: &'static str,
    source_path: &'static str,
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct ParityCase {
    fixture_id: &'static str,
    database_path: &'static str,
    credential: CredentialMode,
    feature_ids: &'static [&'static str],
    list_markers: &'static [&'static str],
    show_expectations: &'static [ShowExpectation],
    attachment_expectations: &'static [AttachmentExpectation],
    xml_markers: &'static [&'static str],
    show_totp_entry_path: Option<&'static str>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct KnownGapExpectation {
    fixture_id: &'static str,
    feature_id: &'static str,
    reason: &'static str,
}

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

static KNOWN_GAP_EXPECTATIONS: [KnownGapExpectation; 0] = [];

fn supported_official_cases() -> Vec<ParityCase> {
    vec![
        ParityCase {
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
            list_markers: &["Fixtures", "BasicEntry"],
            show_expectations: &BASIC_SHOW,
            attachment_expectations: &[],
            xml_markers: &[],
            show_totp_entry_path: None,
        },
        ParityCase {
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
            list_markers: &[],
            show_expectations: &[],
            attachment_expectations: &[],
            xml_markers: &[],
            show_totp_entry_path: None,
        },
        ParityCase {
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
            list_markers: &[],
            show_expectations: &[],
            attachment_expectations: &[],
            xml_markers: &[],
            show_totp_entry_path: None,
        },
        ParityCase {
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
            list_markers: &[
                "Fixtures",
                "Nested",
                "StandardEntry",
                "CustomFieldsEntry",
                "ProtectedEntry",
                "TOTPEntry",
                "AutoTypeEntry",
            ],
            show_expectations: &RICH_SHOW,
            attachment_expectations: &[],
            xml_markers: &[],
            show_totp_entry_path: Some("Fixtures/Nested/TOTPEntry"),
        },
        ParityCase {
            fixture_id: "keepassxc-attachments",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-attachments.kdbx",
            credential: CredentialMode::PasswordOnly,
            feature_ids: &["attachments_by_hash", "standard_fields", "group_tree"],
            list_markers: &["Attachments", "AttachmentEntry"],
            show_expectations: &[],
            attachment_expectations: &ATTACHMENT_EXPORTS,
            xml_markers: &[],
            show_totp_entry_path: None,
        },
        ParityCase {
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
            list_markers: &["HistoryEntry", "Recycle Bin"],
            show_expectations: &[],
            attachment_expectations: &[],
            xml_markers: &[
                "<History>",
                "<DeletedObject>",
                "HistoryEntry",
                "Recycle Bin",
            ],
            show_totp_entry_path: None,
        },
    ]
}

fn kdbx_header_version(path: &str) -> Result<String, Box<dyn std::error::Error>> {
    let mut header = [0u8; 12];
    File::open(project_root().join(path))?.read_exact(&mut header)?;

    let signature1 = u32::from_le_bytes(header[0..4].try_into()?);
    let signature2 = u32::from_le_bytes(header[4..8].try_into()?);
    if signature1 != 0x9aa2d903 || signature2 != 0xb54bfb67 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            format!("{path} does not start with a KDBX signature"),
        )
        .into());
    }

    let version = u32::from_le_bytes(header[8..12].try_into()?);
    let major = version >> 16;
    let minor = version & 0xffff;
    Ok(format!("KDBX{major}.{minor}"))
}

fn known_gap_baseline_set() -> BTreeSet<(&'static str, &'static str)> {
    KNOWN_GAP_BASELINE.into_iter().collect()
}

fn live_known_gap_set() -> BTreeSet<(&'static str, &'static str)> {
    KNOWN_GAP_EXPECTATIONS
        .iter()
        .map(|gap| (gap.fixture_id, gap.feature_id))
        .collect()
}

#[test]
fn official_fixture_versions_are_explicit() -> Result<(), Box<dyn std::error::Error>> {
    let expected = [
        (
            "fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-basic.kdbx",
            "KDBX4.0",
        ),
        (
            "fixtures/compat/official/keepassxc/2.7.12/keepassxc-keyfile-basic.kdbx",
            "KDBX4.0",
        ),
        (
            "fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-keyfile.kdbx",
            "KDBX4.0",
        ),
        (
            "fixtures/compat/official/keepassxc/2.7.12/keepassxc-attachments.kdbx",
            "KDBX4.0",
        ),
        (
            "fixtures/compat/official/keepassxc/2.7.12/keepassxc-richcontent.kdbx",
            "KDBX4.1",
        ),
        (
            "fixtures/compat/official/keepassxc/2.7.12/keepassxc-history-recycle-deleted.kdbx",
            "KDBX4.0",
        ),
    ];

    for (path, version) in expected {
        assert_eq!(
            kdbx_header_version(path)?,
            version,
            "unexpected KDBX header version for {path}"
        );
    }

    Ok(())
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
fn parity_case_model_covers_supported_fixtures() -> Result<(), Box<dyn std::error::Error>> {
    let cases = supported_official_cases();
    let actual_ids = cases.iter().map(|case| case.fixture_id).collect::<Vec<_>>();
    assert_eq!(
        actual_ids, SUPPORTED_OFFICIAL_FIXTURE_IDS,
        " parity cases must match the supported KeePassXC fixtures exactly"
    );

    let manifest = load_manifest(&project_root().join("fixtures/compat/manifest.json"))?;
    let expected_ids = SUPPORTED_OFFICIAL_FIXTURE_IDS
        .into_iter()
        .collect::<BTreeSet<_>>();
    let supported_manifest_ids = manifest
        .fixtures
        .iter()
        .filter(|fixture| {
            fixture.source_tool == "keepassxc-cli"
                && fixture.support_status == SupportStatus::Supported
        })
        .map(|fixture| fixture.fixture_id.as_str())
        .collect::<BTreeSet<_>>();
    assert_eq!(
        supported_manifest_ids, expected_ids,
        "manifest-supported KeePassXC CLI fixtures drifted from parity case expectations"
    );

    for case in &cases {
        assert!(
            project_root().join(case.database_path).is_file(),
            "missing parity database artifact for {}",
            case.fixture_id
        );
        match case.credential {
            CredentialMode::PasswordOnly => {}
            CredentialMode::KeyFileOnly { key_file }
            | CredentialMode::PasswordAndKeyFile { key_file } => assert!(
                project_root().join(key_file).is_file(),
                "missing parity key-file artifact for {}",
                case.fixture_id
            ),
        }
    }

    let basic = parity_case(&cases, "keepassxc-password-basic");
    assert_case_has_markers(basic.list_markers, &["Fixtures", "BasicEntry"]);
    assert_case_has_show_markers(
        basic,
        "Fixtures/BasicEntry",
        &[
            "fixture-user",
            "https://manykee.test/basic",
            "Synthetic basic entry",
        ],
    );

    let rich = parity_case(&cases, "keepassxc-richcontent");
    assert_case_has_markers(
        rich.list_markers,
        &[
            "Fixtures",
            "Nested",
            "StandardEntry",
            "CustomFieldsEntry",
            "ProtectedEntry",
            "TOTPEntry",
            "AutoTypeEntry",
        ],
    );
    assert_case_has_show_markers(
        rich,
        "Fixtures/Nested/CustomFieldsEntry",
        &["manykee-custom-field", "custom-field-value"],
    );
    assert_case_has_show_markers(
        rich,
        "Fixtures/Nested/TOTPEntry",
        &["TOTPEntry", "totp-user"],
    );
    assert_eq!(
        rich.show_totp_entry_path,
        Some("Fixtures/Nested/TOTPEntry"),
        "rich-content fixture must run a KeePassXC --totp smoke check"
    );

    let attachments = parity_case(&cases, "keepassxc-attachments");
    assert_eq!(
        attachments.attachment_expectations, &ATTACHMENT_EXPORTS,
        "attachment fixture must declare both export/hash expectations"
    );

    let history = parity_case(&cases, "keepassxc-history-recycle-deleted");
    assert_case_has_markers(
        history.xml_markers,
        &[
            "<History>",
            "<DeletedObject>",
            "HistoryEntry",
            "Recycle Bin",
        ],
    );

    Ok(())
}

#[test]
fn manual_pending_and_optional_lanes_are_not_required_parity_inputs(
) -> Result<(), Box<dyn std::error::Error>> {
    let case_ids = supported_official_cases()
        .iter()
        .map(|case| case.fixture_id)
        .collect::<BTreeSet<_>>();
    let manual_pending_ids = [
        "keepassxc-gui-argon2id-aes",
        "keepassxc-gui-argon2d-chacha20",
        "keepassxc-gui-argon2id-twofish",
        "keepassxc-unknownxml",
    ];
    for fixture_id in manual_pending_ids {
        assert!(
            !case_ids.contains(fixture_id),
            "{fixture_id} must not be a required parity input"
        );
    }

    let root = project_root();
    let manifest = load_manifest(&root.join("fixtures/compat/manifest.json"))?;
    for fixture_id in manual_pending_ids {
        let fixture = manifest
            .fixtures
            .iter()
            .find(|fixture| fixture.fixture_id == fixture_id)
            .unwrap_or_else(|| panic!("missing manual-pending manifest fixture {fixture_id}"));
        assert_eq!(fixture.support_status, SupportStatus::ManualPending);
    }

    let evidence = load_evidence_dir(&root.join("fixtures/compat/evidence"))?;
    let keepass_optional_claims = evidence
        .iter()
        .flat_map(|record| {
            record.claims.iter().filter_map(|claim| {
                let claim_fixture_id = claim.fixture_id.as_deref().unwrap_or(&record.fixture_id);
                let claim_lane = claim.lane.unwrap_or(record.lane);
                (claim_fixture_id.starts_with("keepassxc-")
                    && claim_lane == EvidenceLane::KeepassOptional)
                    .then_some(claim)
            })
        })
        .collect::<Vec<_>>();
    assert!(
        !keepass_optional_claims.is_empty(),
        "optional evidence lane must remain visible in manifest/evidence data"
    );
    assert!(
        keepass_optional_claims
            .iter()
            .all(|claim| claim.status == SupportStatus::NotObserved),
        "optional evidence lane must stay non-required and not_observed"
    );

    Ok(())
}

#[test]
fn official_tool_calls_use_shared_helper_policy() -> Result<(), Box<dyn std::error::Error>> {
    let source_path = project_root().join("rust/keepassxc/tests/bidirectional_parity.rs");
    let source = std::fs::read_to_string(source_path)?;
    let direct_command = ["Command::new(", "\"keepassxc-cli\"", ")"].concat();
    let direct_stdio = ["Stdio", "::", "piped"].concat();
    let shared_module = ["mod ", "common;"].concat();
    let shared_runner = ["run_keepassxc", "_with_stdin_lines"].concat();

    assert!(
        source.contains(&shared_module),
        "Bidirectional parity tests must import shared official-tool helpers"
    );
    assert!(
        source.contains(&shared_runner),
        "Bidirectional parity tests must use shared official-tool runner"
    );
    assert!(
        !source.contains(&direct_command),
        "Bidirectional parity tests must not spawn keepassxc-cli directly"
    );
    assert!(
        !source.contains(&direct_stdio),
        "Bidirectional parity tests must not manage official-tool stdio directly"
    );

    Ok(())
}

#[test]
fn credential_modes_build_manykee_keys() -> Result<(), Box<dyn std::error::Error>> {
    for case in supported_official_cases() {
        let key = database_key(&case)?;
        let mut file = File::open(project_root().join(case.database_path))?;
        Database::open(&mut file, key).map_err(|err| {
            std::io::Error::new(
                std::io::ErrorKind::Other,
                format!(
                    "failed to open {} with its parity credential mode: {err}",
                    case.fixture_id
                ),
            )
        })?;
    }

    Ok(())
}

#[test]
fn official_to_manykee_preserves_supported_semantics() -> Result<(), Box<dyn std::error::Error>> {
    for case in supported_official_cases() {
        let db = open_case_database(&case)?;
        let before = snapshot(&db);
        let tempdir = tempfile::tempdir()?;
        let saved_path = tempdir
            .path()
            .join(format!("{}-manykee.kdbx", case.fixture_id));

        match save_case_database(&db, &case, &saved_path) {
            Ok(()) => {
                let reopened = reopen_case_database(&case, &saved_path)?;
                let after = snapshot(&reopened);
                assert_supported_snapshot_fields(&case, &before, &after);
            }
            Err(err) if is_expected_save_known_gap(&case, err.as_ref()) => {
                report_known_gaps_for_case(&case, err.as_ref());
            }
            Err(err) => return Err(err),
        }
    }

    Ok(())
}

#[test]
fn official_to_manykee_to_keepassxc_supported_fixtures() -> Result<(), Box<dyn std::error::Error>> {
    let Some(tool) = keepassxc_tool_or_skip() else {
        return Ok(());
    };

    for case in supported_official_cases() {
        let db = open_case_database(&case)?;
        let tempdir = tempfile::tempdir()?;
        let saved_path = tempdir
            .path()
            .join(format!("{}-manykee.kdbx", case.fixture_id));

        match save_case_database(&db, &case, &saved_path) {
            Ok(()) => {
                reopen_case_database(&case, &saved_path)?;
                inspect_manykee_saved_case_with_keepassxc(&tool, &case, &saved_path)?;
            }
            Err(err) if is_expected_save_known_gap(&case, err.as_ref()) => {
                report_known_gaps_for_case(&case, err.as_ref());
            }
            Err(err) => return Err(err),
        }
    }

    Ok(())
}

#[test]
fn manykee_saved_richcontent_show_totp_is_recognized_by_keepassxc(
) -> Result<(), Box<dyn std::error::Error>> {
    let Some(tool) = keepassxc_tool_or_skip() else {
        return Ok(());
    };

    let cases = supported_official_cases();
    let case = parity_case(&cases, "keepassxc-richcontent");
    let db = open_case_database(case)?;
    let before = snapshot(&db);
    let before_totp = totp_values(&before);
    assert!(
        before_totp
            .contains("otpauth://totp/ManyKee:fixture?secret=JBSWY3DPEHPK3PXP&issuer=ManyKee"),
        "source rich-content fixture must contain the expected TOTP URI: {before_totp:?}"
    );

    let tempdir = tempfile::tempdir()?;
    let saved_path = tempdir.path().join("keepassxc-richcontent-manykee.kdbx");
    save_case_database(&db, case, &saved_path)?;

    let reopened = reopen_case_database(case, &saved_path)?;
    let after = snapshot(&reopened);
    let after_totp = totp_values(&after);
    assert_eq!(
        before_totp, after_totp,
        "ManyKee save/reopen must preserve rich-content TOTP CustomData"
    );

    let totp_output = run_keepassxc_case(
        &tool,
        case,
        "show",
        &saved_path,
        &[OsString::from("--totp")],
        &[OsString::from("Fixtures/Nested/TOTPEntry")],
    )?;
    assert_keepassxc_success(case, "show --totp", &totp_output);
    assert!(
        !totp_output.stdout.trim().is_empty(),
        "KeePassXC show --totp should print a TOTP code"
    );

    Ok(())
}

#[test]
fn manykee_to_keepassxc_to_manykee_created_database() -> Result<(), Box<dyn std::error::Error>> {
    let Some(tool) = keepassxc_tool_or_skip() else {
        return Ok(());
    };

    let password = "manykee-parity-password";
    let db = create_manykee_parity_basic_database();
    let before = snapshot(&db);
    let tempdir = tempfile::tempdir()?;
    let saved_path = tempdir.path().join("manykee-created-parity.kdbx");

    {
        let mut file = File::create(&saved_path)?;
        db.save(&mut file, DatabaseKey::new().with_password(password))?;
    }

    inspect_manykee_written_database_with_keepassxc(
        &tool,
        &saved_path,
        password,
        &[
            "ManyKee Parity",
            "ManyKee",
            "ManyKeeGeneratedEntry",
            "manykee-user",
            "manykee-generated-password",
            "https://manykee.test/generated",
            "Generated by ManyKee parity gate",
            "manykee-generated-field",
            "generated-value",
            "bidirectional",
            "manykee-write",
        ],
    )?;

    let reopened = open_manykee_written_database(&saved_path, password)?;
    let after = snapshot(&reopened);
    assert_manykee_written_snapshot(&before, &after, &["/Root/ManyKee/ManyKeeGeneratedEntry"]);

    Ok(())
}

#[test]
fn manykee_to_keepassxc_to_manykee_starter_fixture() -> Result<(), Box<dyn std::error::Error>> {
    let Some(tool) = keepassxc_tool_or_skip() else {
        return Ok(());
    };

    let db = open_manykee_fixture_database(STARTER_RICHCONTENT_PATH, STARTER_RICHCONTENT_PASSWORD)?;
    let before = snapshot(&db);
    let tempdir = tempfile::tempdir()?;
    let saved_path = tempdir.path().join("starter-richcontent-manykee.kdbx");

    {
        let mut file = File::create(&saved_path)?;
        db.save(
            &mut file,
            DatabaseKey::new().with_password(STARTER_RICHCONTENT_PASSWORD),
        )?;
    }

    inspect_manykee_written_database_with_keepassxc(
        &tool,
        &saved_path,
        STARTER_RICHCONTENT_PASSWORD,
        &[
            "ManyKee Test Database",
            "Level1Group",
            "Level2Group",
            "StandardEntry",
            "CustomFieldsEntry",
            "CustomField1",
            "custom_value_1",
            "AutoTypeEntry",
            "TaggedEntry",
            "work",
            "important",
            "AttachmentEntry",
            "TOTPEntry",
            "HistoryEntry",
        ],
    )?;

    let reopened = open_manykee_written_database(&saved_path, STARTER_RICHCONTENT_PASSWORD)?;
    let after = snapshot(&reopened);
    assert_manykee_written_snapshot(
        &before,
        &after,
        &[
            "/Root/Level1Group/Level2Group/StandardEntry",
            "/Root/Level1Group/CustomFieldsEntry",
            "/Root/AutoTypeEntry",
            "/Root/TaggedEntry",
            "/Root/AttachmentEntry",
            "/Root/TOTPEntry",
            "/Root/HistoryEntry",
        ],
    );

    Ok(())
}

fn create_manykee_parity_basic_database() -> Database {
    let mut db = Database::new(DatabaseConfig::default());
    db.meta.database_name = Some("ManyKee Parity".to_string());

    let mut group = Group::new("ManyKee");
    let mut entry = Entry::new();
    entry.set_unprotected(fields::TITLE, "ManyKeeGeneratedEntry");
    entry.set_unprotected(fields::USERNAME, "manykee-user");
    entry.set_protected(fields::PASSWORD, "manykee-generated-password");
    entry.set_unprotected(fields::URL, "https://manykee.test/generated");
    entry.set_unprotected(fields::NOTES, "Generated by ManyKee parity gate");
    entry.set_unprotected("manykee-generated-field", "generated-value");
    entry.tags = vec!["bidirectional".to_string(), "manykee-write".to_string()];
    group.entries.push(entry);
    db.root.groups.push(group);

    db
}

fn open_manykee_fixture_database(
    relative_path: &str,
    password: &str,
) -> Result<Database, Box<dyn std::error::Error>> {
    open_manykee_written_database(&project_root().join(relative_path), password)
}

fn open_manykee_written_database(
    path: &Path,
    password: &str,
) -> Result<Database, Box<dyn std::error::Error>> {
    let mut file = File::open(path)?;
    Ok(Database::open(
        &mut file,
        DatabaseKey::new().with_password(password),
    )?)
}

fn inspect_manykee_written_database_with_keepassxc(
    tool: &OfficialTool,
    database_path: &Path,
    password: &str,
    expected_markers: &[&str],
) -> Result<(), Box<dyn std::error::Error>> {
    let mut combined_output = String::new();

    let db_info =
        run_keepassxc_password_database(tool, "db-info", database_path, password, &[], &[])?;
    assert_manykee_keepassxc_success("db-info", &db_info, password);
    combined_output.push_str(&db_info.stdout);
    combined_output.push_str(&db_info.stderr);

    let listing = run_keepassxc_password_database(tool, "ls", database_path, password, &[], &[])?;
    assert_manykee_keepassxc_success("ls -R -f", &listing, password);
    combined_output.push_str(&listing.stdout);
    combined_output.push_str(&listing.stderr);

    let mut successful_show_count = 0usize;
    for entry_path in manykee_written_show_entry_paths() {
        let show_output = run_keepassxc_password_database(
            tool,
            "show",
            database_path,
            password,
            &[OsString::from("--all"), OsString::from("-s")],
            &[OsString::from(entry_path)],
        )?;

        if show_output.status.success() {
            successful_show_count += 1;
            combined_output.push_str(&show_output.stdout);
            combined_output.push_str(&show_output.stderr);
        }
    }

    assert!(
        successful_show_count > 0,
        "KeePassXC show --all -s did not find any expected ManyKee-written entries"
    );

    for marker in expected_markers {
        assert!(
            combined_output.contains(marker),
            "KeePassXC inspection output missing marker {marker}:\n{combined_output}"
        );
    }

    Ok(())
}

fn run_keepassxc_password_database(
    tool: &OfficialTool,
    command: &str,
    database_path: &Path,
    password: &str,
    command_options: &[OsString],
    trailing_args: &[OsString],
) -> Result<RedactedOutput, Box<dyn std::error::Error>> {
    let mut args = vec![OsString::from(command), OsString::from("-q")];
    if command == "ls" {
        args.push(OsString::from("-R"));
        args.push(OsString::from("-f"));
    }
    args.extend(command_options.iter().cloned());
    args.push(database_path.as_os_str().to_os_string());
    args.extend(trailing_args.iter().cloned());

    Ok(run_keepassxc_with_stdin_lines(
        tool,
        &args,
        &[password],
        &[password],
    )?)
}

fn assert_manykee_keepassxc_success(command: &str, output: &RedactedOutput, password: &str) {
    assert!(
        output.status.success(),
        "KeePassXC {command} failed:\nstdout:\n{}\nstderr:\n{}",
        output.stdout,
        output.stderr
    );
    assert!(!output.stdout.contains(password));
    assert!(!output.stderr.contains(password));
}

fn manykee_written_show_entry_paths() -> &'static [&'static str] {
    &[
        "ManyKee/ManyKeeGeneratedEntry",
        "Level1Group/Level2Group/StandardEntry",
        "Level1Group/CustomFieldsEntry",
        "AutoTypeEntry",
        "TaggedEntry",
        "AttachmentEntry",
        "TOTPEntry",
        "HistoryEntry",
    ]
}

fn assert_manykee_written_snapshot(
    before: &SemanticSnapshot,
    after: &SemanticSnapshot,
    expected_entry_paths: &[&str],
) {
    assert_eq!(
        group_uuid_snapshot(before),
        group_uuid_snapshot(after),
        "group UUIDs changed after ManyKee write/reopen"
    );
    assert_eq!(
        entry_uuid_snapshot(before),
        entry_uuid_snapshot(after),
        "entry UUIDs changed after ManyKee write/reopen"
    );
    assert_eq!(
        group_tree_snapshot(before),
        group_tree_snapshot(after),
        "group tree changed after ManyKee write/reopen"
    );
    assert_eq!(
        standard_field_snapshot(before),
        standard_field_snapshot(after),
        "standard fields changed after ManyKee write/reopen"
    );
    assert_eq!(
        custom_field_snapshot(before),
        custom_field_snapshot(after),
        "custom fields changed after ManyKee write/reopen"
    );
    assert_eq!(
        protected_flag_snapshot(before),
        protected_flag_snapshot(after),
        "protected flags changed after ManyKee write/reopen"
    );
    assert_eq!(
        tag_snapshot(before),
        tag_snapshot(after),
        "tags changed after ManyKee write/reopen"
    );
    assert_eq!(
        metadata_snapshot(before),
        metadata_snapshot(after),
        "metadata changed after ManyKee write/reopen"
    );
    assert_eq!(
        attachments_by_hash_snapshot(before),
        attachments_by_hash_snapshot(after),
        "attachments changed after ManyKee write/reopen"
    );
    assert_eq!(
        autotype_snapshot(before),
        autotype_snapshot(after),
        "Auto-Type metadata changed after ManyKee write/reopen"
    );
    assert_eq!(
        custom_data_snapshot(before),
        custom_data_snapshot(after),
        "CustomData changed after ManyKee write/reopen"
    );
    assert_eq!(
        history_snapshot(before),
        history_snapshot(after),
        "history changed after ManyKee write/reopen"
    );

    for expected_entry_path in expected_entry_paths {
        assert!(
            after
                .entries
                .iter()
                .any(|entry| entry.path == *expected_entry_path),
            "reopened ManyKee-written database missing entry path {expected_entry_path}"
        );
    }
}

fn group_uuid_snapshot(snapshot: &SemanticSnapshot) -> BTreeMap<String, String> {
    snapshot
        .groups
        .iter()
        .map(|group| (group.path.clone(), group.uuid.clone()))
        .collect()
}

fn entry_uuid_snapshot(snapshot: &SemanticSnapshot) -> BTreeMap<String, String> {
    snapshot
        .entries
        .iter()
        .map(|entry| (entry.path.clone(), entry.uuid.clone()))
        .collect()
}

fn parity_case<'a>(cases: &'a [ParityCase], fixture_id: &str) -> &'a ParityCase {
    cases
        .iter()
        .find(|case| case.fixture_id == fixture_id)
        .unwrap_or_else(|| panic!("missing parity case {fixture_id}"))
}

fn assert_case_has_markers(actual: &[&str], expected: &[&str]) {
    for marker in expected {
        assert!(actual.contains(marker), "missing expected marker {marker}");
    }
}

fn assert_case_has_show_markers(case: &ParityCase, entry_path: &str, expected: &[&str]) {
    let show = case
        .show_expectations
        .iter()
        .find(|show| show.entry_path == entry_path)
        .unwrap_or_else(|| panic!("missing show expectation for {entry_path}"));
    assert_case_has_markers(show.markers, expected);
}

fn database_key(case: &ParityCase) -> Result<DatabaseKey, Box<dyn std::error::Error>> {
    let key = match case.credential {
        CredentialMode::PasswordOnly => DatabaseKey::new().with_password(FIXTURE_PASSWORD),
        CredentialMode::KeyFileOnly { key_file } => {
            DatabaseKey::new().with_keyfile(&mut File::open(project_root().join(key_file))?)?
        }
        CredentialMode::PasswordAndKeyFile { key_file } => DatabaseKey::new()
            .with_password(FIXTURE_PASSWORD)
            .with_keyfile(&mut File::open(project_root().join(key_file))?)?,
    };

    Ok(key)
}

fn open_case_database(case: &ParityCase) -> Result<Database, Box<dyn std::error::Error>> {
    let mut file = File::open(project_root().join(case.database_path))?;
    Ok(Database::open(&mut file, database_key(case)?)?)
}

fn save_case_database(
    db: &Database,
    case: &ParityCase,
    path: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut file = File::create(path)?;
    db.save(&mut file, database_key(case)?)?;
    Ok(())
}

fn reopen_case_database(
    case: &ParityCase,
    path: &Path,
) -> Result<Database, Box<dyn std::error::Error>> {
    let mut file = File::open(path)?;
    Ok(Database::open(&mut file, database_key(case)?)?)
}

fn snapshot(db: &Database) -> SemanticSnapshot {
    semantic_snapshot::snapshot_database(db)
}

fn assert_supported_snapshot_fields(
    case: &ParityCase,
    before: &SemanticSnapshot,
    after: &SemanticSnapshot,
) {
    for feature_id in case.feature_ids {
        match *feature_id {
            "credential_password_only"
            | "credential_key_file_only"
            | "credential_password_key_file"
            | "cipher_aes256"
            | "kdf_aes" => {}
            "group_tree" => assert_eq!(
                group_tree_snapshot(before),
                group_tree_snapshot(after),
                "{} group_tree changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "standard_fields" => assert_eq!(
                standard_field_snapshot(before),
                standard_field_snapshot(after),
                "{} standard_fields changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "custom_fields" => assert_eq!(
                custom_field_snapshot(before),
                custom_field_snapshot(after),
                "{} custom_fields changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "protected_flags" => assert_eq!(
                protected_flag_snapshot(before),
                protected_flag_snapshot(after),
                "{} protected_flags changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "tags" => assert_eq!(
                tag_snapshot(before),
                tag_snapshot(after),
                "{} tags changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "metadata" => assert_eq!(
                metadata_snapshot(before),
                metadata_snapshot(after),
                "{} metadata changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "attachments_by_hash" => assert_eq!(
                attachments_by_hash_snapshot(before),
                attachments_by_hash_snapshot(after),
                "{} attachments_by_hash changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "history" => assert_eq!(
                history_snapshot(before),
                history_snapshot(after),
                "{} history changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "deleted_objects" => {
                let before_keys = deleted_object_keys(before);
                let after_keys = deleted_object_keys(after);
                if before_keys == after_keys && !before_keys.is_empty() {
                    continue;
                }
                if let Some(gap) = known_gap(case.fixture_id, "deleted_objects") {
                    eprintln!(
                        "KNOWN GAP: fixture={} feature={} reason={} before_keys={:?} after_keys={:?}",
                        gap.fixture_id, gap.feature_id, gap.reason, before_keys, after_keys
                    );
                } else {
                    assert_eq!(
                        before_keys, after_keys,
                        "{} deleted_objects changed after ManyKee save/reopen",
                        case.fixture_id
                    );
                    assert!(
                        !before_keys.is_empty(),
                        "{} deleted_objects feature expected observable DeletedObject keys",
                        case.fixture_id
                    );
                }
            }
            "autotype_metadata" => assert_eq!(
                autotype_snapshot(before),
                autotype_snapshot(after),
                "{} autotype_metadata changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "custom_data" => assert_eq!(
                custom_data_snapshot(before),
                custom_data_snapshot(after),
                "{} custom_data changed after ManyKee save/reopen",
                case.fixture_id
            ),
            "totp" => assert_eq!(
                totp_values(before),
                totp_values(after),
                "{} totp custom data changed after ManyKee save/reopen",
                case.fixture_id
            ),
            other => panic!(
                "{} has no parity assertion branch for feature {other}",
                case.fixture_id
            ),
        }
    }
}

fn is_expected_save_known_gap(case: &ParityCase, err: &(dyn std::error::Error + 'static)) -> bool {
    let error_text = format!("{err:?} {err}");
    let is_unsupported_version = error_text.contains("UnsupportedVersion")
        || error_text
            .to_ascii_lowercase()
            .contains("unsupported database version");
    is_unsupported_version
        && case
            .feature_ids
            .iter()
            .all(|feature_id| known_gap(case.fixture_id, feature_id).is_some())
}

fn report_known_gaps_for_case(case: &ParityCase, err: &(dyn std::error::Error + 'static)) {
    for feature_id in case.feature_ids {
        let gap = known_gap(case.fixture_id, feature_id).unwrap_or_else(|| {
            panic!(
                "{} save failed with {err}, but feature {feature_id} has no KnownGapExpectation",
                case.fixture_id
            )
        });
        eprintln!(
            "KNOWN GAP: fixture={} feature={} reason={} observed_error={}",
            gap.fixture_id, gap.feature_id, gap.reason, err
        );
    }
}

fn known_gap(fixture_id: &str, feature_id: &str) -> Option<&'static KnownGapExpectation> {
    KNOWN_GAP_EXPECTATIONS
        .iter()
        .find(|gap| gap.fixture_id == fixture_id && gap.feature_id == feature_id)
}

fn group_tree_snapshot(snapshot: &SemanticSnapshot) -> BTreeMap<String, Vec<String>> {
    snapshot
        .groups
        .iter()
        .map(|group| {
            (
                group.path.clone(),
                group
                    .entries
                    .iter()
                    .map(|entry| entry.path.clone())
                    .collect(),
            )
        })
        .collect()
}

fn standard_field_snapshot(
    snapshot: &SemanticSnapshot,
) -> BTreeMap<String, BTreeMap<String, FieldSnapshot>> {
    snapshot
        .entries
        .iter()
        .map(|entry| {
            (
                entry.path.clone(),
                entry
                    .fields
                    .iter()
                    .filter(|(_, field)| field.standard)
                    .map(|(name, field)| (name.clone(), field.clone()))
                    .collect(),
            )
        })
        .collect()
}

fn custom_field_snapshot(
    snapshot: &SemanticSnapshot,
) -> BTreeMap<String, BTreeMap<String, FieldSnapshot>> {
    snapshot
        .entries
        .iter()
        .map(|entry| {
            (
                entry.path.clone(),
                entry
                    .fields
                    .iter()
                    .filter(|(_, field)| !field.standard)
                    .map(|(name, field)| (name.clone(), field.clone()))
                    .collect(),
            )
        })
        .collect()
}

fn protected_flag_snapshot(
    snapshot: &SemanticSnapshot,
) -> BTreeMap<String, BTreeMap<String, bool>> {
    let mut flags = BTreeMap::new();
    for entry in &snapshot.entries {
        flags.insert(
            entry.path.clone(),
            entry
                .fields
                .iter()
                .map(|(name, field)| (name.clone(), field.protected))
                .collect(),
        );
        for (index, history) in entry.history.iter().enumerate() {
            flags.insert(
                format!("{}#history-{index}", entry.path),
                history
                    .fields
                    .iter()
                    .map(|(name, field)| (name.clone(), field.protected))
                    .collect(),
            );
        }
    }
    flags
}

fn tag_snapshot(snapshot: &SemanticSnapshot) -> BTreeMap<String, Option<String>> {
    let mut tags = BTreeMap::new();
    for group in &snapshot.groups {
        tags.insert(format!("group:{}", group.path), group.tags.clone());
    }
    for entry in &snapshot.entries {
        tags.insert(format!("entry:{}", entry.path), Some(entry.tags.join(",")));
    }
    tags
}

fn metadata_snapshot(
    snapshot: &SemanticSnapshot,
) -> (
    Option<String>,
    Option<String>,
    Option<String>,
    MemoryProtectionSnapshot,
    BTreeMap<String, CustomDataSnapshot>,
) {
    (
        snapshot.metadata.database_name.clone(),
        snapshot.metadata.database_description.clone(),
        snapshot.metadata.default_username.clone(),
        snapshot.metadata.memory_protection.clone(),
        snapshot.metadata.custom_data.clone(),
    )
}

fn attachments_by_hash_snapshot(
    snapshot: &SemanticSnapshot,
) -> BTreeMap<String, Vec<AttachmentSnapshot>> {
    snapshot
        .entries
        .iter()
        .map(|entry| (entry.path.clone(), entry.attachments.clone()))
        .collect()
}

fn history_snapshot(
    snapshot: &SemanticSnapshot,
) -> BTreeMap<String, Vec<BTreeMap<String, String>>> {
    snapshot
        .entries
        .iter()
        .map(|entry| {
            (
                entry.path.clone(),
                entry
                    .history
                    .iter()
                    .map(|history| {
                        history
                            .fields
                            .iter()
                            .filter(|(_, field)| field.standard)
                            .map(|(name, field)| (name.clone(), field.value.clone()))
                            .collect()
                    })
                    .collect(),
            )
        })
        .collect()
}

fn deleted_object_keys(snapshot: &SemanticSnapshot) -> BTreeSet<String> {
    snapshot.deleted_objects.keys().cloned().collect()
}

fn autotype_snapshot(snapshot: &SemanticSnapshot) -> BTreeMap<String, Option<AutoTypeSnapshot>> {
    snapshot
        .entries
        .iter()
        .map(|entry| (entry.path.clone(), entry.autotype.clone()))
        .collect()
}

fn custom_data_snapshot(
    snapshot: &SemanticSnapshot,
) -> BTreeMap<String, BTreeMap<String, CustomDataSnapshot>> {
    let mut custom_data = BTreeMap::new();
    custom_data.insert(
        "metadata".to_string(),
        snapshot.metadata.custom_data.clone(),
    );
    for group in &snapshot.groups {
        custom_data.insert(format!("group:{}", group.path), group.custom_data.clone());
    }
    for entry in &snapshot.entries {
        custom_data.insert(format!("entry:{}", entry.path), entry.custom_data.clone());
    }
    custom_data
}

fn totp_values(snapshot: &SemanticSnapshot) -> BTreeSet<String> {
    snapshot
        .entries
        .iter()
        .flat_map(|entry| entry.custom_data.values())
        .filter_map(|custom_data| custom_data.value.as_deref())
        .filter(|value| value.contains("otpauth://totp/ManyKee:fixture"))
        .map(str::to_string)
        .collect()
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

fn keepassxc_args_for_case(
    case: &ParityCase,
    command: &str,
    database_path: &Path,
    command_options: &[OsString],
    trailing_args: &[OsString],
) -> Vec<OsString> {
    let mut args = vec![OsString::from(command), OsString::from("-q")];
    if command == "ls" {
        args.push(OsString::from("-R"));
        args.push(OsString::from("-f"));
    }
    args.extend(command_options.iter().cloned());

    match case.credential {
        CredentialMode::PasswordOnly => {}
        CredentialMode::KeyFileOnly { key_file } => {
            args.push(OsString::from("--no-password"));
            args.push(OsString::from("--key-file"));
            args.push(project_root().join(key_file).into_os_string());
        }
        CredentialMode::PasswordAndKeyFile { key_file } => {
            args.push(OsString::from("--key-file"));
            args.push(project_root().join(key_file).into_os_string());
        }
    }

    args.push(database_path.as_os_str().to_os_string());
    args.extend(trailing_args.iter().cloned());
    args
}

fn keepassxc_stdin_lines(case: &ParityCase) -> Vec<&'static str> {
    match case.credential {
        CredentialMode::PasswordOnly | CredentialMode::PasswordAndKeyFile { .. } => {
            vec![FIXTURE_PASSWORD]
        }
        CredentialMode::KeyFileOnly { .. } => Vec::new(),
    }
}

fn run_keepassxc_case(
    tool: &OfficialTool,
    case: &ParityCase,
    command: &str,
    database_path: &Path,
    command_options: &[OsString],
    trailing_args: &[OsString],
) -> Result<RedactedOutput, Box<dyn std::error::Error>> {
    const REDACTIONS: [&str; 4] = [
        FIXTURE_PASSWORD,
        "manykee-entry-password",
        "manykee-entry-password-edited",
        "manykee-rich-protected-value",
    ];

    let args =
        keepassxc_args_for_case(case, command, database_path, command_options, trailing_args);
    let stdin_lines = keepassxc_stdin_lines(case);
    Ok(run_keepassxc_with_stdin_lines(
        tool,
        &args,
        &stdin_lines,
        &REDACTIONS,
    )?)
}

fn inspect_manykee_saved_case_with_keepassxc(
    tool: &OfficialTool,
    case: &ParityCase,
    database_path: &Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let db_info = run_keepassxc_case(tool, case, "db-info", database_path, &[], &[])?;
    assert_keepassxc_success(case, "db-info", &db_info);

    let listing = run_keepassxc_case(tool, case, "ls", database_path, &[], &[])?;
    assert_keepassxc_success(case, "ls -R -f", &listing);
    for marker in case.list_markers {
        assert!(
            listing.stdout.contains(marker),
            "{} KeePassXC ls output missing marker {marker}:\n{}",
            case.fixture_id,
            listing.stdout
        );
    }

    for show in case.show_expectations {
        let show_output = run_keepassxc_case(
            tool,
            case,
            "show",
            database_path,
            &[OsString::from("--all"), OsString::from("-s")],
            &[OsString::from(show.entry_path)],
        )?;
        assert_keepassxc_success(case, "show --all -s", &show_output);
        for marker in show.markers {
            assert!(
                show_output.stdout.contains(marker),
                "{} KeePassXC show output for {} missing marker {marker}:\n{}",
                case.fixture_id,
                show.entry_path,
                show_output.stdout
            );
        }
    }

    if let Some(entry_path) = case.show_totp_entry_path {
        let totp_output = run_keepassxc_case(
            tool,
            case,
            "show",
            database_path,
            &[OsString::from("--totp")],
            &[OsString::from(entry_path)],
        )?;
        if totp_output.status.success() {
            assert_keepassxc_success(case, "show --totp", &totp_output);
        } else if let Some(gap) = known_gap(case.fixture_id, "totp") {
            eprintln!(
                "KNOWN GAP: fixture={} feature={} reason={} observed_stderr={}",
                gap.fixture_id, gap.feature_id, gap.reason, totp_output.stderr
            );
        } else {
            assert_keepassxc_success(case, "show --totp", &totp_output);
        }
    }

    if !case.xml_markers.is_empty() {
        let export_output = run_keepassxc_case(
            tool,
            case,
            "export",
            database_path,
            &[OsString::from("-f"), OsString::from("xml")],
            &[],
        )?;
        assert_keepassxc_success(case, "export -f xml", &export_output);
        for marker in case.xml_markers {
            if export_output.stdout.contains(marker) {
                continue;
            }
            if marker.contains("DeletedObject") {
                if let Some(gap) = known_gap(case.fixture_id, "deleted_objects") {
                    eprintln!(
                        "KNOWN GAP: fixture={} feature={} reason={} missing_xml_marker={}",
                        gap.fixture_id, gap.feature_id, gap.reason, marker
                    );
                    continue;
                }
            }
            panic!(
                "{} KeePassXC XML export missing marker {marker}:\n{}",
                case.fixture_id, export_output.stdout
            );
        }
    }

    if !case.attachment_expectations.is_empty() {
        let tempdir = tempfile::tempdir()?;
        for attachment in case.attachment_expectations {
            let exported = tempdir.path().join(attachment.attachment_name);
            let export_output = run_keepassxc_case(
                tool,
                case,
                "attachment-export",
                database_path,
                &[],
                &[
                    OsString::from(attachment.entry_path),
                    OsString::from(attachment.attachment_name),
                    exported.as_os_str().to_os_string(),
                ],
            )?;
            assert_keepassxc_success(case, "attachment-export", &export_output);
            assert_eq!(
                artifact_sha256(&project_root().join(attachment.source_path))?,
                artifact_sha256(&exported)?,
                "{} attachment-export hash mismatch for {}",
                case.fixture_id,
                attachment.attachment_name
            );
        }
    }

    Ok(())
}

fn assert_keepassxc_success(case: &ParityCase, command: &str, output: &RedactedOutput) {
    assert!(
        output.status.success(),
        "{} KeePassXC {command} failed:\nstdout:\n{}\nstderr:\n{}",
        case.fixture_id,
        output.stdout,
        output.stderr
    );
    assert!(!output.stdout.contains(FIXTURE_PASSWORD));
    assert!(!output.stderr.contains(FIXTURE_PASSWORD));
}

fn project_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}
