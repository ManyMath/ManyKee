use keepassxc::compat_evidence::{
    artifact_sha256, check_manifest_section, load_evidence_dir, load_manifest, merge_manifest,
    render_matrix_from_paths, validate_source_backing, CompatibilityManifest, EvidenceLane,
    EvidenceRecord, FeatureClaim, FeatureRow, FixtureArtifact, FixtureGeneration, FixtureMetadata,
    ManifestSection, SupportStatus,
};
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use tempfile::TempDir;

#[test]
fn schema_parses_manifest_and_evidence() {
    let temp = TempDir::new().expect("tempdir should be created");
    let manifest_path = temp.path().join("manifest.json");
    let evidence_dir = temp.path().join("evidence");
    fs::create_dir(&evidence_dir).expect("evidence dir should be created");

    fs::write(
        &manifest_path,
        r#"{
  "schema_version": 1,
  "fixtures": [
    {
      "fixture_id": "tiny-fixture",
      "source_path": "tests/resources/tiny.kdbx",
      "credential_ref": "synthetic password fixture",
      "provenance": "inline test manifest",
      "notes": ["schema smoke"]
    }
  ],
  "features": [
    {
      "feature_id": "group_tree",
      "name": "Group tree",
      "description": "Nested group paths and ordering",
      "lanes": ["keepass_xc", "keepass_optional", "many_kee_read", "many_kee_write"],
      "notes": []
    }
  ],
  "known_gaps": [],
  "non_goals": [],
  "unsupported": [],
  "not_observed": [],
  "notes": ["test manifest"]
}"#,
    )
    .expect("manifest should be written");

    fs::write(
        evidence_dir.join("manykee-read.json"),
        r#"{
  "schema_version": 1,
  "evidence_id": "tiny-read",
  "fixture_id": "tiny-fixture",
  "lane": "many_kee_read",
  "tool_name": "manykee",
  "tool_version": "0.1.0",
  "status": "supported",
  "snapshot_path": "fixtures/compat/snapshots/tiny-read.semantic.json",
  "snapshot_sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "evidence_path": "fixtures/compat/evidence/manykee-read.json",
  "claims": [
    {
      "feature_id": "group_tree",
      "status": "supported",
      "notes": ["read path observed"]
    }
  ],
  "known_gaps": [],
  "non_goals": [],
  "notes": []
}"#,
    )
    .expect("manykee evidence should be written");

    fs::write(
        evidence_dir.join("keepassxc-not-observed.json"),
        r#"{
  "schema_version": 1,
  "evidence_id": "tiny-keepassxc",
  "fixture_id": "tiny-fixture",
  "lane": "keepass_xc",
  "tool_name": "keepassxc-cli",
  "tool_version": "2.7.12",
  "status": "not_observed",
  "snapshot_path": null,
  "snapshot_sha256": null,
  "evidence_path": "fixtures/compat/evidence/keepassxc-not-observed.json",
  "claims": [
    {
      "feature_id": "group_tree",
      "status": "not_observed",
      "notes": ["official-created fixture not generated here"]
    }
  ],
  "known_gaps": [],
  "non_goals": [],
  "notes": []
}"#,
    )
    .expect("keepassxc evidence should be written");

    let manifest = load_manifest(&manifest_path).expect("manifest should parse");
    let evidence = load_evidence_dir(&evidence_dir).expect("evidence should parse");

    assert_eq!(manifest.schema_version, 1);
    assert_eq!(manifest.fixtures[0].fixture_id, "tiny-fixture");
    assert_eq!(
        manifest.features[0].lanes,
        vec![
            EvidenceLane::KeepassXc,
            EvidenceLane::KeepassOptional,
            EvidenceLane::ManyKeeRead,
            EvidenceLane::ManyKeeWrite,
        ]
    );
    assert_eq!(evidence[0].lane, EvidenceLane::KeepassXc);
    assert_eq!(evidence[0].status, SupportStatus::NotObserved);
    assert_eq!(evidence[1].lane, EvidenceLane::ManyKeeRead);
    assert_eq!(evidence[1].status, SupportStatus::Supported);
}

#[test]
fn source_backing_rejects_unbacked_claim() {
    let temp = TempDir::new().expect("tempdir should be created");
    let manifest_path = temp.path().join("manifest.json");

    fs::write(
        &manifest_path,
        r#"{
  "schema_version": 1,
  "fixtures": [
    {
      "fixture_id": "tiny-fixture",
      "source_path": "tests/resources/tiny.kdbx",
      "credential_ref": "synthetic password fixture",
      "provenance": "inline test manifest",
      "notes": []
    }
  ],
  "features": [
    {
      "feature_id": "group_tree",
      "name": "Group tree",
      "description": "Nested group paths and ordering",
      "lanes": ["many_kee_read"],
      "notes": []
    }
  ],
  "known_gaps": [],
  "non_goals": [],
  "unsupported": [],
  "not_observed": [],
  "notes": []
}"#,
    )
    .expect("manifest should be written");

    let manifest = load_manifest(&manifest_path).expect("manifest should parse");
    let err = validate_source_backing(&manifest, &[]).expect_err("missing source should fail");

    assert!(
        err.to_string().contains("missing source backing"),
        "unexpected error: {err}"
    );
}

#[test]
fn schema_parses_official_fixture_metadata() {
    let temp = TempDir::new().expect("tempdir should be created");
    let manifest_path = temp.path().join("manifest.json");

    fs::write(
        &manifest_path,
        r#"{
  "schema_version": 2,
  "fixtures": [
    {
      "fixture_id": "keepassxc-password-basic",
      "source_path": "fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-basic.kdbx",
      "credential_ref": "synthetic password fixture: manykee-fixture-password",
      "provenance": "Generated by KeePassXC CLI 2.7.12 for fixture metadata tests.",
      "source_tool": "keepassxc-cli",
      "source_version": "2.7.12",
      "feature_ids": [
        "credential_password_only",
        "cipher_aes256",
        "kdf_aes",
        "group_tree",
        "standard_fields"
      ],
      "artifacts": [
        {
          "path": "fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-basic.kdbx",
          "kind": "kdbx",
          "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        }
      ],
      "generation": {
        "kind": "cli",
        "command": "keepassxc-cli db-create -q -p <database>",
        "stdin": ["<password>", "<password>"],
        "manual_steps": [],
        "notes": ["stdin values are placeholders, not raw secrets"]
      },
      "expected_assertions": [
        "keepassxc db-info reports Cipher: AES 256-bit",
        "semantic snapshot contains one group and one entry"
      ],
      "support_status": "supported",
      "notes": ["inline schema test"]
    }
  ],
  "features": [],
  "known_gaps": [],
  "non_goals": [],
  "unsupported": [],
  "not_observed": [],
  "notes": []
}"#,
    )
    .expect("manifest should be written");

    let manifest = load_manifest(&manifest_path).expect("manifest should parse");
    let fixture = &manifest.fixtures[0];

    assert_eq!(manifest.schema_version, 2);
    assert_eq!(fixture.fixture_id, "keepassxc-password-basic");
    assert_eq!(fixture.source_tool, "keepassxc-cli");
    assert_eq!(fixture.source_version, "2.7.12");
    assert_eq!(fixture.support_status, SupportStatus::Supported);
    assert_eq!(
        fixture.feature_ids,
        vec![
            "credential_password_only",
            "cipher_aes256",
            "kdf_aes",
            "group_tree",
            "standard_fields",
        ]
    );
    assert_eq!(fixture.artifacts[0].kind, "kdbx");
    assert_eq!(fixture.artifacts[0].sha256.len(), 64);
    assert!(fixture.artifacts[0]
        .sha256
        .chars()
        .all(|ch| ch.is_ascii_hexdigit() && !ch.is_ascii_uppercase()));
    assert_eq!(fixture.generation.kind, "cli");
    assert_eq!(
        fixture.generation.command.as_deref(),
        Some("keepassxc-cli db-create -q -p <database>")
    );
    assert_eq!(fixture.generation.stdin.len(), 2);
    assert_eq!(fixture.expected_assertions.len(), 2);
}

#[test]
fn source_backing_uses_fixture_feature_ids() {
    let manifest = CompatibilityManifest {
        schema_version: 2,
        fixtures: vec![fixture_metadata(
            "keepassxc-password-basic",
            vec!["credential_password_only"],
            SupportStatus::Supported,
        )],
        features: vec![
            feature_row("credential_password_only", vec![EvidenceLane::ManyKeeRead]),
            feature_row("attachments_by_hash", vec![EvidenceLane::ManyKeeRead]),
        ],
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        unsupported: Vec::new(),
        not_observed: Vec::new(),
        notes: Vec::new(),
    };
    let evidence = vec![EvidenceRecord {
        schema_version: 2,
        evidence_id: "password-basic-read".to_string(),
        fixture_id: "keepassxc-password-basic".to_string(),
        lane: EvidenceLane::ManyKeeRead,
        tool_name: "manykee".to_string(),
        tool_version: "0.1.0".to_string(),
        status: SupportStatus::Supported,
        snapshot_path: None,
        snapshot_sha256: None,
        evidence_path: Some("fixtures/compat/evidence/password-basic-read.json".to_string()),
        claims: vec![FeatureClaim {
            feature_id: "credential_password_only".to_string(),
            status: SupportStatus::Supported,
            fixture_id: None,
            lane: None,
            evidence_path: None,
            notes: Vec::new(),
        }],
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        notes: Vec::new(),
    }];

    validate_source_backing(&manifest, &evidence)
        .expect("omitted fixture feature should not require source backing");
}

#[test]
fn manual_pending_status_is_supported() {
    let temp = TempDir::new().expect("tempdir should be created");
    let manifest_path = temp.path().join("manifest.json");
    let evidence_dir = temp.path().join("evidence");
    fs::create_dir(&evidence_dir).expect("evidence dir should be created");

    fs::write(
        &manifest_path,
        r#"{
  "schema_version": 2,
  "fixtures": [
    {
      "fixture_id": "keepassxc-gui-argon2id-aes",
      "source_path": "fixtures/compat/official/keepassxc/2.7.12/manual/keepassxc-gui-argon2id-aes.kdbx",
      "credential_ref": "synthetic password fixture: manykee-fixture-password",
      "provenance": "GUI fixture metadata is pending manual capture.",
      "source_tool": "keepassxc-gui",
      "source_version": "2.7.12",
      "feature_ids": ["cipher_aes256"],
      "artifacts": [],
      "generation": {
        "kind": "manual_pending",
        "command": null,
        "stdin": [],
        "manual_steps": ["Create a KDBX4 database in KeePassXC GUI with Argon2id and AES."],
        "notes": []
      },
      "expected_assertions": ["manual fixture will assert AES and Argon2id once captured"],
      "support_status": "manual_pending",
      "notes": []
    }
  ],
  "features": [
    {
      "feature_id": "cipher_aes256",
      "name": "AES-256 cipher",
      "description": "AES-256 encrypted KDBX4 database.",
      "lanes": ["keepass_xc"],
      "notes": []
    }
  ],
  "known_gaps": [],
  "non_goals": [],
  "unsupported": [],
  "not_observed": [
    {
      "feature_id": "cipher_aes256",
      "status": "manual_pending",
      "fixture_id": "keepassxc-gui-argon2id-aes",
      "lane": "keepass_xc",
      "notes": ["GUI capture pending"]
    }
  ],
  "notes": []
}"#,
    )
    .expect("manifest should be written");

    let manifest = load_manifest(&manifest_path).expect("manifest should parse");
    assert_eq!(
        manifest.fixtures[0].support_status,
        SupportStatus::ManualPending
    );

    let matrix = render_matrix_from_paths(&manifest_path, &evidence_dir)
        .expect("manual pending matrix should render");
    assert!(matrix.contains("manual_pending"));
    assert!(matrix.contains("not_applicable"));
}

#[test]
fn committed_manual_pending_metadata_is_source_backed() {
    let project_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let manifest_path = project_root.join("fixtures/compat/manifest.json");
    let evidence_dir = project_root.join("fixtures/compat/evidence");

    let manifest = load_manifest(&manifest_path).expect("committed manifest should parse");
    let evidence = load_evidence_dir(&evidence_dir).expect("committed evidence should parse");
    validate_source_backing(&manifest, &evidence)
        .expect("manual pending claims should be source-backed");

    for fixture_id in [
        "keepassxc-gui-argon2id-aes",
        "keepassxc-gui-argon2d-chacha20",
        "keepassxc-gui-argon2id-twofish",
        "keepassxc-unknownxml",
    ] {
        let fixture = manifest
            .fixtures
            .iter()
            .find(|fixture| fixture.fixture_id == fixture_id)
            .unwrap_or_else(|| panic!("missing committed manual pending fixture {fixture_id}"));
        assert_eq!(fixture.support_status, SupportStatus::ManualPending);
        assert_eq!(fixture.generation.kind, "manual_pending");

        let has_keepassxc_manual_pending_claim = evidence.iter().any(|record| {
            record.claims.iter().any(|claim| {
                let claim_fixture_id = claim.fixture_id.as_deref().unwrap_or(&record.fixture_id);
                let claim_lane = claim.lane.unwrap_or(record.lane);
                claim_fixture_id == fixture_id
                    && claim_lane == EvidenceLane::KeepassXc
                    && claim.status == SupportStatus::ManualPending
            })
        });
        assert!(
            has_keepassxc_manual_pending_claim,
            "{fixture_id} missing KeePassXC manual_pending evidence claim"
        );
    }

    let matrix = render_matrix_from_paths(&manifest_path, &evidence_dir)
        .expect("committed manual pending matrix should render");
    assert!(matrix.contains("keepassxc-gui-argon2d-chacha20"));
    assert!(matrix.contains("manual_pending"));
}

#[test]
fn keepass_optional_evidence_is_not_observed() {
    let project_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let evidence = load_evidence_dir(&project_root.join("fixtures/compat/evidence"))
        .expect("committed evidence should parse");
    let record = evidence
        .iter()
        .find(|record| record.evidence_id == "keepass-optional-cipher-kdf-not-observed")
        .expect("missing optional KeePass evidence");

    assert_eq!(record.lane, EvidenceLane::KeepassOptional);
    assert_eq!(record.status, SupportStatus::NotObserved);
    assert!(record
        .claims
        .iter()
        .all(|claim| claim.status == SupportStatus::NotObserved));
    assert!(record
        .notes
        .iter()
        .any(|note| note.contains("KeePass 2.61")));
    assert!(record.notes.iter().any(|note| note.contains("KPScript")));

    let manifest = load_manifest(&project_root.join("fixtures/compat/manifest.json"))
        .expect("committed manifest should parse");
    validate_source_backing(&manifest, &evidence)
        .expect("optional KeePass not_observed claims should be source-backed");
}

#[test]
fn manifest_section_merge_preserves_unowned_fixtures() {
    let old_starter = fixture_metadata(
        "starter-richcontent",
        vec!["group_tree"],
        SupportStatus::Partial,
    );
    let mut new_starter = old_starter.clone();
    new_starter.source_path = "fixtures/starter-new.kdbx".to_string();
    let official_fixture = fixture_metadata(
        "keepassxc-password-basic",
        vec!["credential_password_only"],
        SupportStatus::Supported,
    );
    let existing = CompatibilityManifest {
        schema_version: 2,
        fixtures: vec![old_starter, official_fixture.clone()],
        features: vec![
            feature_row("group_tree", vec![EvidenceLane::ManyKeeRead]),
            feature_row("credential_password_only", vec![EvidenceLane::KeepassXc]),
        ],
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        unsupported: Vec::new(),
        not_observed: Vec::new(),
        notes: vec!["official recorder note".to_string()],
    };
    let section = starter_manifest_section(new_starter.clone());

    let merged = merge_manifest(Some(existing), &section);

    assert_eq!(merged.schema_version, 2);
    assert!(merged
        .fixtures
        .iter()
        .any(|fixture| fixture == &official_fixture));
    assert!(merged
        .fixtures
        .iter()
        .any(|fixture| fixture == &new_starter));
    check_manifest_section(&merged, &section).expect("owned starter section should match");
}

#[test]
fn manifest_section_check_ignores_unowned_fixtures() {
    let starter = fixture_metadata("starter-richcontent", vec!["group_tree"], SupportStatus::Partial);
    let mut stale_official = fixture_metadata(
        "keepassxc-password-basic",
        vec!["credential_password_only"],
        SupportStatus::Supported,
    );
    stale_official.source_path = "fixtures/stale-official.kdbx".to_string();
    let section = starter_manifest_section(starter.clone());
    let actual = CompatibilityManifest {
        schema_version: 2,
        fixtures: vec![starter.clone(), stale_official],
        features: vec![
            feature_row("group_tree", vec![EvidenceLane::ManyKeeRead]),
            feature_row("credential_password_only", vec![EvidenceLane::KeepassXc]),
        ],
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        unsupported: Vec::new(),
        not_observed: Vec::new(),
        notes: Vec::new(),
    };

    check_manifest_section(&actual, &section)
        .expect("unowned official fixture staleness should be ignored");

    let mut stale_owned = actual.clone();
    stale_owned.fixtures[0].source_path = "fixtures/stale-starter.kdbx".to_string();
    assert!(check_manifest_section(&stale_owned, &section).is_err());
}

#[test]
fn source_backing() {
    let project_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let manifest_path = project_root.join("fixtures/compat/manifest.json");
    let evidence_dir = project_root.join("fixtures/compat/evidence");

    let manifest = load_manifest(&manifest_path).expect("committed manifest should parse");
    let evidence = load_evidence_dir(&evidence_dir).expect("committed evidence should parse");

    validate_source_backing(&manifest, &evidence).expect("committed claims should be backed");

    let lanes: BTreeSet<EvidenceLane> = evidence.iter().map(|record| record.lane).collect();
    assert_eq!(
        lanes,
        BTreeSet::from([
            EvidenceLane::KeepassXc,
            EvidenceLane::KeepassOptional,
            EvidenceLane::ManyKeeRead,
            EvidenceLane::ManyKeeWrite,
        ])
    );

    for record in &evidence {
        if let Some(snapshot_path) = &record.snapshot_path {
            let snapshot_path = project_root.join(snapshot_path);
            assert!(
                snapshot_path.exists(),
                "snapshot does not exist: {}",
                snapshot_path.display()
            );
            assert_eq!(
                record.snapshot_sha256.as_deref(),
                Some(
                    artifact_sha256(&snapshot_path)
                        .expect("snapshot should hash")
                        .as_str()
                ),
                "snapshot hash mismatch for {}",
                snapshot_path.display()
            );
        }
    }
}

#[test]
fn committed_starter_manifest_uses_expanded_schema() {
    let project_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let manifest_path = project_root.join("fixtures/compat/manifest.json");
    let source_path = "rust/keepassxc/tests/resources/test_db_kdbx4_richcontent.kdbx";

    let manifest = load_manifest(&manifest_path).expect("committed manifest should parse");
    let fixture = manifest
        .fixtures
        .iter()
        .find(|fixture| fixture.fixture_id == "starter-richcontent")
        .expect("starter-richcontent fixture should exist");
    let artifact = fixture
        .artifacts
        .iter()
        .find(|artifact| artifact.path == source_path)
        .expect("starter kdbx artifact should be recorded");

    assert_eq!(manifest.schema_version, 2);
    assert_eq!(fixture.source_tool, "manykee-starter");
    assert_eq!(fixture.source_version, env!("CARGO_PKG_VERSION"));
    assert_eq!(fixture.support_status, SupportStatus::Partial);
    assert!(fixture
        .provenance
        .contains("not the broad official KeePassXC corpus"));
    assert!(fixture
        .feature_ids
        .contains(&"group_tree".to_string()));
    assert!(fixture
        .feature_ids
        .contains(&"broad_official_fixture_corpus".to_string()));
    assert_eq!(artifact.kind, "kdbx");
    assert_eq!(
        artifact.sha256,
        artifact_sha256(&project_root.join(source_path)).expect("starter fixture should hash")
    );
    assert_eq!(fixture.generation.kind, "preexisting");
    assert!(fixture.generation.command.is_none());
    assert!(fixture.generation.stdin.is_empty());
    assert!(!fixture.expected_assertions.is_empty());

    let broad_official_statuses: BTreeSet<SupportStatus> = manifest
        .not_observed
        .iter()
        .filter(|claim| {
            claim.fixture_id.as_deref() == Some("starter-richcontent")
                && claim.feature_id == "broad_official_fixture_corpus"
        })
        .map(|claim| claim.status)
        .collect();
    assert_eq!(
        broad_official_statuses,
        BTreeSet::from([SupportStatus::NotObserved])
    );
}

fn fixture_metadata(
    fixture_id: &str,
    feature_ids: Vec<&str>,
    support_status: SupportStatus,
) -> FixtureMetadata {
    FixtureMetadata {
        fixture_id: fixture_id.to_string(),
        source_path: format!("fixtures/{fixture_id}.kdbx"),
        credential_ref: "synthetic password fixture: manykee-fixture-password".to_string(),
        provenance: "inline test fixture".to_string(),
        source_tool: "test-tool".to_string(),
        source_version: "1.0.0".to_string(),
        feature_ids: feature_ids.into_iter().map(str::to_string).collect(),
        artifacts: vec![FixtureArtifact {
            path: format!("fixtures/{fixture_id}.kdbx"),
            kind: "kdbx".to_string(),
            sha256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                .to_string(),
        }],
        generation: FixtureGeneration {
            kind: "preexisting".to_string(),
            command: None,
            stdin: Vec::new(),
            manual_steps: Vec::new(),
            notes: Vec::new(),
        },
        expected_assertions: vec!["fixture assertion".to_string()],
        support_status,
        notes: Vec::new(),
    }
}

fn feature_row(feature_id: &str, lanes: Vec<EvidenceLane>) -> FeatureRow {
    FeatureRow {
        feature_id: feature_id.to_string(),
        name: feature_id.replace('_', " "),
        description: format!("{feature_id} description"),
        lanes,
        notes: Vec::new(),
    }
}

fn starter_manifest_section(starter: FixtureMetadata) -> ManifestSection {
    ManifestSection {
        section_id: "starter".to_string(),
        schema_version: 2,
        owned_fixture_ids: BTreeSet::from(["starter-richcontent".to_string()]),
        owned_feature_ids: BTreeSet::from(["group_tree".to_string()]),
        fixtures: vec![starter],
        features: vec![feature_row("group_tree", vec![EvidenceLane::ManyKeeRead])],
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        unsupported: Vec::new(),
        not_observed: Vec::new(),
        notes: vec!["starter recorder note".to_string()],
    }
}

#[test]
fn generated_matrix_is_fresh() {
    let project_root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let manifest_path = project_root.join("fixtures/compat/manifest.json");
    let evidence_dir = project_root.join("fixtures/compat/evidence");
    let matrix_path = project_root.join("docs/compatibility-matrix.md");

    let generated = render_matrix_from_paths(&manifest_path, &evidence_dir)
        .expect("matrix should render from committed manifest and evidence");
    let committed = fs::read_to_string(&matrix_path)
        .expect("committed docs/compatibility-matrix.md should exist");

    assert_eq!(
        generated, committed,
        "docs/compatibility-matrix.md is stale; run scripts/generate_compat_matrix.sh --write"
    );
}
