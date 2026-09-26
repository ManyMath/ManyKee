use keepassxc::compat_evidence::{
    artifact_sha256, check_manifest_section, load_manifest, merge_manifest, EvidenceLane,
    EvidenceRecord, FeatureClaim, FeatureRow, FixtureArtifact, FixtureGeneration, FixtureMetadata,
    ManifestSection, SupportStatus,
};
use keepassxc::{semantic_snapshot, Database, DatabaseKey};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::collections::BTreeSet;
use std::fs::{self, File};
use std::io;
use std::path::{Path, PathBuf};
use std::process;
use tempfile::TempDir;

const FIXTURE_ID: &str = "starter-richcontent";
const RICHCONTENT_PASSWORD: &str = "testpass123";
const SOURCE_PATH: &str = "rust/keepassxc/tests/resources/test_db_kdbx4_richcontent.kdbx";
const MANIFEST_PATH: &str = "fixtures/compat/manifest.json";
const EVIDENCE_DIR: &str = "fixtures/compat/evidence";
const SNAPSHOT_DIR: &str = "fixtures/compat/snapshots";
const MANYKEE_READ_SNAPSHOT: &str =
    "fixtures/compat/snapshots/manykee-richcontent-read.semantic.json";
const MANYKEE_WRITE_SNAPSHOT: &str =
    "fixtures/compat/snapshots/manykee-richcontent-write.semantic.json";
const MANYKEE_READ_EVIDENCE: &str = "fixtures/compat/evidence/manykee-richcontent-read.json";
const MANYKEE_WRITE_EVIDENCE: &str = "fixtures/compat/evidence/manykee-richcontent-write.json";
const KEEPASSXC_EVIDENCE: &str = "fixtures/compat/evidence/keepassxc-richcontent-not-observed.json";
const KEEPASS_OPTIONAL_EVIDENCE: &str =
    "fixtures/compat/evidence/keepass-optional-richcontent-not-observed.json";

type DynError = Box<dyn std::error::Error>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Write,
    Check,
}

struct GeneratedArtifact {
    relative_path: &'static str,
    contents: String,
}

struct GeneratedEvidence {
    manifest_section: ManifestSection,
    snapshots: Vec<GeneratedArtifact>,
    evidence: Vec<GeneratedArtifact>,
}

fn main() {
    let mode = match parse_mode() {
        Ok(mode) => mode,
        Err(message) => {
            eprintln!("{message}");
            eprintln!("usage: record_compat_evidence (--write|--check)");
            process::exit(2);
        }
    };

    if let Err(err) = run(mode) {
        eprintln!("{err}");
        process::exit(1);
    }
}

fn parse_mode() -> Result<Mode, String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.as_slice() {
        [mode] if mode == "--write" => Ok(Mode::Write),
        [mode] if mode == "--check" => Ok(Mode::Check),
        [] => Err("missing mode".to_string()),
        [mode] => Err(format!("unknown mode: {mode}")),
        _ => Err("expected exactly one mode".to_string()),
    }
}

fn run(mode: Mode) -> Result<(), DynError> {
    let project_root = project_root();
    let generated = generate_evidence(&project_root)?;

    match mode {
        Mode::Write => write_generated(&project_root, &generated)?,
        Mode::Check => check_generated(&project_root, &generated)?,
    }

    Ok(())
}

fn generate_evidence(project_root: &Path) -> Result<GeneratedEvidence, DynError> {
    let manifest_section = build_manifest_section(project_root)?;
    let read_snapshot = snapshot_read_fixture(project_root)?;
    let write_snapshot = snapshot_manykee_written_fixture(project_root)?;
    let read_hash = hash_text(&read_snapshot);
    let write_hash = hash_text(&write_snapshot);

    let evidence = vec![
        GeneratedArtifact {
            relative_path: MANYKEE_READ_EVIDENCE,
            contents: pretty_json(&manykee_evidence_record(
                "manykee-richcontent-read",
                EvidenceLane::ManyKeeRead,
                SupportStatus::Partial,
                MANYKEE_READ_SNAPSHOT,
                &read_hash,
                MANYKEE_READ_EVIDENCE,
            )?)?,
        },
        GeneratedArtifact {
            relative_path: MANYKEE_WRITE_EVIDENCE,
            contents: pretty_json(&manykee_evidence_record(
                "manykee-richcontent-write",
                EvidenceLane::ManyKeeWrite,
                SupportStatus::Partial,
                MANYKEE_WRITE_SNAPSHOT,
                &write_hash,
                MANYKEE_WRITE_EVIDENCE,
            )?)?,
        },
        GeneratedArtifact {
            relative_path: KEEPASSXC_EVIDENCE,
            contents: pretty_json(&not_observed_official_record(
                "keepassxc-richcontent-not-observed",
                EvidenceLane::KeepassXc,
                "keepassxc-cli",
                "2.7.12",
                KEEPASSXC_EVIDENCE,
            )?)?,
        },
        GeneratedArtifact {
            relative_path: KEEPASS_OPTIONAL_EVIDENCE,
            contents: pretty_json(&not_observed_official_record(
                "keepass-optional-richcontent-not-observed",
                EvidenceLane::KeepassOptional,
                "keepass-kpscript",
                "2.61 optional",
                KEEPASS_OPTIONAL_EVIDENCE,
            )?)?,
        },
    ];

    Ok(GeneratedEvidence {
        manifest_section,
        snapshots: vec![
            GeneratedArtifact {
                relative_path: MANYKEE_READ_SNAPSHOT,
                contents: read_snapshot,
            },
            GeneratedArtifact {
                relative_path: MANYKEE_WRITE_SNAPSHOT,
                contents: write_snapshot,
            },
        ],
        evidence,
    })
}

fn snapshot_read_fixture(project_root: &Path) -> Result<String, DynError> {
    let db = open_richcontent_fixture(project_root)?;
    snapshot_json(&db)
}

fn snapshot_manykee_written_fixture(project_root: &Path) -> Result<String, DynError> {
    let db = open_richcontent_fixture(project_root)?;
    let temp = TempDir::new()?;
    let saved_path = temp.path().join("manykee-write.kdbx");
    {
        let mut file = File::create(&saved_path)?;
        db.save(
            &mut file,
            DatabaseKey::new().with_password(RICHCONTENT_PASSWORD),
        )?;
    }

    let mut file = File::open(saved_path)?;
    let saved = Database::open(
        &mut file,
        DatabaseKey::new().with_password(RICHCONTENT_PASSWORD),
    )?;
    snapshot_json(&saved)
}

fn open_richcontent_fixture(project_root: &Path) -> Result<Database, DynError> {
    let path = project_root.join(SOURCE_PATH);
    let mut file = File::open(&path)?;
    Ok(Database::open(
        &mut file,
        DatabaseKey::new().with_password(RICHCONTENT_PASSWORD),
    )?)
}

fn snapshot_json(db: &Database) -> Result<String, DynError> {
    let mut json = semantic_snapshot::snapshot_json_pretty(db)?;
    json.push('\n');
    Ok(json)
}

fn write_generated(project_root: &Path, generated: &GeneratedEvidence) -> Result<(), DynError> {
    fs::create_dir_all(project_root.join(EVIDENCE_DIR))?;
    fs::create_dir_all(project_root.join(SNAPSHOT_DIR))?;

    write_manifest_section(project_root, &generated.manifest_section)?;
    for artifact in generated.snapshots.iter().chain(generated.evidence.iter()) {
        write_artifact(project_root, artifact)?;
    }

    Ok(())
}

fn check_generated(project_root: &Path, generated: &GeneratedEvidence) -> Result<(), DynError> {
    check_manifest_section_artifact(project_root, &generated.manifest_section)?;
    for artifact in generated.snapshots.iter().chain(generated.evidence.iter()) {
        check_artifact(project_root, artifact)?;
    }

    Ok(())
}

fn write_manifest_section(project_root: &Path, section: &ManifestSection) -> Result<(), DynError> {
    let path = project_root.join(MANIFEST_PATH);
    let existing = if path.exists() {
        Some(load_manifest(&path)?)
    } else {
        None
    };
    let manifest = merge_manifest(existing, section);
    fs::write(path, pretty_json(&manifest)?)?;
    Ok(())
}

fn check_manifest_section_artifact(
    project_root: &Path,
    section: &ManifestSection,
) -> Result<(), DynError> {
    let path = project_root.join(MANIFEST_PATH);
    let manifest = load_manifest(&path)?;
    check_manifest_section(&manifest, section).map_err(|source| {
        io::Error::other(format!(
                "{MANIFEST_PATH} starter section is stale; run `cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_compat_evidence -- --write`: {source}"
            ),
        )
    })?;
    Ok(())
}

fn write_artifact(project_root: &Path, artifact: &GeneratedArtifact) -> Result<(), DynError> {
    let path = project_root.join(artifact.relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, &artifact.contents)?;
    Ok(())
}

fn check_artifact(project_root: &Path, artifact: &GeneratedArtifact) -> Result<(), DynError> {
    let path = project_root.join(artifact.relative_path);
    let actual = fs::read_to_string(&path).map_err(|source| {
        io::Error::new(
            source.kind(),
            format!("failed to read {}: {source}", artifact.relative_path),
        )
    })?;

    if actual != artifact.contents {
        return Err(io::Error::other(format!(
                "{} is stale; run `cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_compat_evidence -- --write`",
                artifact.relative_path
            ),
        )
        .into());
    }

    Ok(())
}

fn build_manifest_section(project_root: &Path) -> Result<ManifestSection, DynError> {
    let all_lanes = vec![
        EvidenceLane::KeepassXc,
        EvidenceLane::KeepassOptional,
        EvidenceLane::ManyKeeRead,
        EvidenceLane::ManyKeeWrite,
    ];
    let mut features = vec![
        feature(
            "group_tree",
            "Group tree",
            "Nested group names, parent paths, ordering, and group entries.",
        ),
        feature(
            "uuids",
            "UUIDs",
            "Database group, entry, recycle-bin, and deleted-object UUID evidence.",
        ),
        feature(
            "standard_fields",
            "Standard fields",
            "Title, username, password, URL, and notes fields.",
        ),
        feature(
            "custom_fields",
            "Custom fields",
            "Entry string fields outside the KeePass standard field set.",
        ),
        feature(
            "protected_flags",
            "Protected flags",
            "Protected/unprotected memory flags for fields and attachments.",
        ),
        feature(
            "tags",
            "Tags",
            "Entry and group tag values as parsed by the model.",
        ),
        feature(
            "metadata",
            "Metadata",
            "Database-level metadata and memory protection.",
        ),
        feature(
            "timestamps",
            "Timestamps",
            "Creation, modification, access, expiry, and settings timestamps.",
        ),
        feature(
            "attachments_by_hash",
            "Attachments by hash",
            "Attachment names, protection flags, sizes, and SHA-256 hashes.",
        ),
        feature(
            "history",
            "History",
            "Entry history snapshots where present.",
        ),
        feature(
            "deleted_objects",
            "Deleted objects",
            "Deleted-object UUIDs and deletion timestamps.",
        ),
        feature(
            "autotype_metadata",
            "Auto-Type metadata",
            "Auto-Type enabled flags, default sequence, and associations.",
        ),
        feature(
            "custom_icons",
            "Custom icons",
            "Custom icon UUIDs and icon payload SHA-256 hashes where exposed.",
        ),
        feature(
            "custom_data",
            "CustomData",
            "Meta, group, and entry CustomData keys and typed values.",
        ),
        feature(
            "unknown_xml",
            "Unknown XML",
            "Unknown XML exposed by the decrypted model, with current model gaps recorded.",
        ),
        feature(
            "public_custom_data",
            "Public CustomData",
            "DatabaseConfig public CustomData exposure.",
        ),
        feature(
            "byte_identical_output",
            "Byte-identical output",
            "Raw KDBX byte-for-byte output comparison.",
        ),
        feature(
            "broad_official_fixture_corpus",
            "Broad official fixture corpus",
            "Wide KeePassXC-created corpus.",
        ),
    ];
    for feature in &mut features {
        feature.lanes = all_lanes.clone();
    }
    let owned_feature_ids: BTreeSet<String> = features
        .iter()
        .map(|feature| feature.feature_id.clone())
        .collect();
    let feature_ids: Vec<String> = features
        .iter()
        .map(|feature| feature.feature_id.clone())
        .collect();
    let artifact_hash = artifact_sha256(&project_root.join(SOURCE_PATH))?;

    Ok(ManifestSection {
        section_id: "starter".to_string(),
        schema_version: 2,
        owned_fixture_ids: BTreeSet::from([FIXTURE_ID.to_string()]),
        owned_feature_ids,
        fixtures: vec![FixtureMetadata {
            fixture_id: FIXTURE_ID.to_string(),
            source_path: SOURCE_PATH.to_string(),
            credential_ref: "synthetic test password: testpass123".to_string(),
            provenance: "Existing ManyKee rich-content starter fixture used to prove schema and recorder behavior; not the broad official KeePassXC corpus.".to_string(),
            source_tool: "manykee-starter".to_string(),
            source_version: env!("CARGO_PKG_VERSION").to_string(),
            feature_ids,
            artifacts: vec![FixtureArtifact {
                path: SOURCE_PATH.to_string(),
                kind: "kdbx".to_string(),
                sha256: artifact_hash,
            }],
            generation: FixtureGeneration {
                kind: "preexisting".to_string(),
                command: None,
                stdin: Vec::new(),
                manual_steps: Vec::new(),
                notes: vec![
                    "Starter fixture predates the official KeePassXC corpus; this recorder computes its artifact hash from the committed KDBX file.".to_string(),
                ],
            },
            expected_assertions: vec![
                "ManyKee read snapshot records group tree, standard fields, attachments, history, deleted objects, Auto-Type metadata, custom icons, and CustomData evidence.".to_string(),
                "ManyKee write snapshot preserves the same supported semantic categories after save and reopen.".to_string(),
                "Official KeePassXC and optional KeePass lanes remain not_observed for this starter fixture until official corpus fixtures are added.".to_string(),
            ],
            support_status: SupportStatus::Partial,
            notes: vec![
                "Generated starter evidence is intentionally small; expands official KeePassXC-created fixtures.".to_string(),
                "Synthetic credential is documented only for reproducible local fixture generation.".to_string(),
            ],
        }],
        features,
        known_gaps: vec![
            manifest_claim(
                "unknown_xml",
                EvidenceLane::ManyKeeRead,
                SupportStatus::KnownGap,
                "Current snapshot records exposed unknown XML but marks outer attributes unsupported by the model.",
            ),
            manifest_claim(
                "unknown_xml",
                EvidenceLane::ManyKeeWrite,
                SupportStatus::KnownGap,
                "Current snapshot records exposed unknown XML but marks outer attributes unsupported by the model.",
            ),
        ],
        non_goals: all_lanes
            .iter()
            .map(|lane| {
                manifest_claim(
                    "byte_identical_output",
                    *lane,
                    SupportStatus::NonGoal,
                    "KDBX saves legitimately regenerate cryptographic material; semantic comparison is the v1.6 target.",
                )
            })
            .collect(),
        unsupported: Vec::new(),
        not_observed: all_lanes
            .iter()
            .map(|lane| {
                manifest_claim(
                    "broad_official_fixture_corpus",
                    *lane,
                    SupportStatus::NotObserved,
                    "Broad official fixture generation is deferred to the official fixture corpus gate.",
                )
            })
            .collect(),
        notes: vec![
            "Compatibility rows are generated from this manifest plus committed evidence records; do not hand-edit support claims.".to_string(),
            "KeePassXC, optional KeePass, ManyKee read, and ManyKee write lanes are separate evidence sources.".to_string(),
        ],
    })
}

fn feature(feature_id: &str, name: &str, description: &str) -> FeatureRow {
    FeatureRow {
        feature_id: feature_id.to_string(),
        name: name.to_string(),
        description: description.to_string(),
        lanes: Vec::new(),
        notes: Vec::new(),
    }
}

fn manifest_claim(
    feature_id: &str,
    lane: EvidenceLane,
    status: SupportStatus,
    note: &str,
) -> FeatureClaim {
    FeatureClaim {
        feature_id: feature_id.to_string(),
        status,
        fixture_id: Some(FIXTURE_ID.to_string()),
        lane: Some(lane),
        evidence_path: None,
        notes: vec![note.to_string()],
    }
}

fn manykee_evidence_record(
    evidence_id: &str,
    lane: EvidenceLane,
    status: SupportStatus,
    snapshot_path: &str,
    snapshot_sha256: &str,
    evidence_path: &str,
) -> Result<EvidenceRecord, DynError> {
    Ok(EvidenceRecord {
        schema_version: 1,
        evidence_id: evidence_id.to_string(),
        fixture_id: FIXTURE_ID.to_string(),
        lane,
        tool_name: "manykee".to_string(),
        tool_version: env!("CARGO_PKG_VERSION").to_string(),
        status,
        snapshot_path: Some(snapshot_path.to_string()),
        snapshot_sha256: Some(snapshot_sha256.to_string()),
        evidence_path: Some(evidence_path.to_string()),
        claims: manykee_claims(evidence_path),
        known_gaps: vec!["unknown_xml".to_string()],
        non_goals: vec!["byte_identical_output".to_string()],
        notes: vec![
            "Generated from the existing rich-content fixture using the manifest credential_ref."
                .to_string(),
            "Snapshot hash is SHA-256 over the committed semantic JSON artifact.".to_string(),
        ],
    })
}

fn manykee_claims(evidence_path: &str) -> Vec<FeatureClaim> {
    let supported = [
        "group_tree",
        "uuids",
        "standard_fields",
        "custom_fields",
        "protected_flags",
        "tags",
        "metadata",
        "timestamps",
        "attachments_by_hash",
        "history",
        "deleted_objects",
        "autotype_metadata",
        "custom_icons",
        "custom_data",
    ];
    let mut claims: Vec<FeatureClaim> = supported
        .iter()
        .map(|feature_id| evidence_claim(feature_id, SupportStatus::Supported, evidence_path))
        .collect();
    claims.push(evidence_claim(
        "unknown_xml",
        SupportStatus::Partial,
        evidence_path,
    ));
    claims.push(evidence_claim(
        "public_custom_data",
        SupportStatus::NotObserved,
        evidence_path,
    ));
    claims
}

fn not_observed_official_record(
    evidence_id: &str,
    lane: EvidenceLane,
    tool_name: &str,
    tool_version: &str,
    evidence_path: &str,
) -> Result<EvidenceRecord, DynError> {
    Ok(EvidenceRecord {
        schema_version: 1,
        evidence_id: evidence_id.to_string(),
        fixture_id: FIXTURE_ID.to_string(),
        lane,
        tool_name: tool_name.to_string(),
        tool_version: tool_version.to_string(),
        status: SupportStatus::NotObserved,
        snapshot_path: None,
        snapshot_sha256: None,
        evidence_path: Some(evidence_path.to_string()),
        claims: official_not_observed_claims(evidence_path),
        known_gaps: Vec::new(),
        non_goals: vec!["byte_identical_output".to_string()],
        notes: vec![
            "Official-created rich-content fixture behavior is not observed in starter evidence.".to_string(),
            "Broad official corpus generation and required official-tool execution remain deferred to the official fixture corpus and later parity gates.".to_string(),
        ],
    })
}

fn official_not_observed_claims(evidence_path: &str) -> Vec<FeatureClaim> {
    [
        "group_tree",
        "uuids",
        "standard_fields",
        "custom_fields",
        "protected_flags",
        "tags",
        "metadata",
        "timestamps",
        "attachments_by_hash",
        "history",
        "deleted_objects",
        "autotype_metadata",
        "custom_icons",
        "custom_data",
        "unknown_xml",
        "public_custom_data",
        "broad_official_fixture_corpus",
    ]
    .iter()
    .map(|feature_id| evidence_claim(feature_id, SupportStatus::NotObserved, evidence_path))
    .collect()
}

fn evidence_claim(feature_id: &str, status: SupportStatus, evidence_path: &str) -> FeatureClaim {
    FeatureClaim {
        feature_id: feature_id.to_string(),
        status,
        fixture_id: None,
        lane: None,
        evidence_path: Some(evidence_path.to_string()),
        notes: Vec::new(),
    }
}

fn pretty_json<T: Serialize>(value: &T) -> Result<String, DynError> {
    let mut json = serde_json::to_string_pretty(value)?;
    json.push('\n');
    Ok(json)
}

fn hash_text(contents: &str) -> String {
    hex::encode(Sha256::digest(contents.as_bytes()))
}

fn project_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}
