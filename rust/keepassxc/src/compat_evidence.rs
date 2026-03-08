//! Compatibility evidence schemas and source-backing validation.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvidenceLane {
    KeepassXc,
    KeepassOptional,
    ManyKeeRead,
    ManyKeeWrite,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SupportStatus {
    Supported,
    Partial,
    Unsupported,
    NotObserved,
    KnownGap,
    NonGoal,
    Manual,
    ManualPending,
}

impl Default for SupportStatus {
    fn default() -> Self {
        Self::NotObserved
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompatibilityManifest {
    pub schema_version: u32,
    #[serde(default)]
    pub fixtures: Vec<FixtureMetadata>,
    #[serde(default)]
    pub features: Vec<FeatureRow>,
    #[serde(default)]
    pub known_gaps: Vec<FeatureClaim>,
    #[serde(default)]
    pub non_goals: Vec<FeatureClaim>,
    #[serde(default)]
    pub unsupported: Vec<FeatureClaim>,
    #[serde(default)]
    pub not_observed: Vec<FeatureClaim>,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FixtureMetadata {
    pub fixture_id: String,
    pub source_path: String,
    pub credential_ref: String,
    pub provenance: String,
    #[serde(default)]
    pub source_tool: String,
    #[serde(default)]
    pub source_version: String,
    #[serde(default)]
    pub feature_ids: Vec<String>,
    #[serde(default)]
    pub artifacts: Vec<FixtureArtifact>,
    #[serde(default)]
    pub generation: FixtureGeneration,
    #[serde(default)]
    pub expected_assertions: Vec<String>,
    #[serde(default)]
    pub support_status: SupportStatus,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FixtureArtifact {
    pub path: String,
    pub kind: String,
    pub sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FixtureGeneration {
    pub kind: String,
    #[serde(default)]
    pub command: Option<String>,
    #[serde(default)]
    pub stdin: Vec<String>,
    #[serde(default)]
    pub manual_steps: Vec<String>,
    #[serde(default)]
    pub notes: Vec<String>,
}

impl Default for FixtureGeneration {
    fn default() -> Self {
        Self {
            kind: "preexisting".to_string(),
            command: None,
            stdin: Vec::new(),
            manual_steps: Vec::new(),
            notes: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FeatureRow {
    pub feature_id: String,
    pub name: String,
    pub description: String,
    #[serde(default)]
    pub lanes: Vec<EvidenceLane>,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EvidenceRecord {
    pub schema_version: u32,
    pub evidence_id: String,
    pub fixture_id: String,
    pub lane: EvidenceLane,
    pub tool_name: String,
    pub tool_version: String,
    pub status: SupportStatus,
    #[serde(default)]
    pub snapshot_path: Option<String>,
    #[serde(default)]
    pub snapshot_sha256: Option<String>,
    #[serde(default)]
    pub evidence_path: Option<String>,
    #[serde(default)]
    pub claims: Vec<FeatureClaim>,
    #[serde(default)]
    pub known_gaps: Vec<String>,
    #[serde(default)]
    pub non_goals: Vec<String>,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FeatureClaim {
    pub feature_id: String,
    pub status: SupportStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fixture_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lane: Option<EvidenceLane>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub evidence_path: Option<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ManifestSection {
    pub section_id: String,
    pub schema_version: u32,
    pub owned_fixture_ids: BTreeSet<String>,
    pub owned_feature_ids: BTreeSet<String>,
    pub fixtures: Vec<FixtureMetadata>,
    pub features: Vec<FeatureRow>,
    pub known_gaps: Vec<FeatureClaim>,
    pub non_goals: Vec<FeatureClaim>,
    pub unsupported: Vec<FeatureClaim>,
    pub not_observed: Vec<FeatureClaim>,
    pub notes: Vec<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum CompatEvidenceError {
    #[error("failed to read {path}: {source}")]
    Read {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("failed to list evidence directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("failed to parse JSON {path}: {source}")]
    Json {
        path: PathBuf,
        source: serde_json::Error,
    },
    #[error(
        "missing source backing for fixture '{fixture_id}', feature '{feature_id}', lane '{lane:?}'"
    )]
    MissingSourceBacking {
        fixture_id: String,
        feature_id: String,
        lane: EvidenceLane,
    },
    #[error("manifest section '{section_id}' mismatch: {reason}")]
    ManifestSectionMismatch { section_id: String, reason: String },
}

pub fn load_manifest(path: &Path) -> Result<CompatibilityManifest, CompatEvidenceError> {
    let data = fs::read_to_string(path).map_err(|source| CompatEvidenceError::Read {
        path: path.to_path_buf(),
        source,
    })?;
    serde_json::from_str(&data).map_err(|source| CompatEvidenceError::Json {
        path: path.to_path_buf(),
        source,
    })
}

pub fn load_evidence_dir(path: &Path) -> Result<Vec<EvidenceRecord>, CompatEvidenceError> {
    let mut paths = fs::read_dir(path)
        .map_err(|source| CompatEvidenceError::ReadDir {
            path: path.to_path_buf(),
            source,
        })?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|source| CompatEvidenceError::ReadDir {
            path: path.to_path_buf(),
            source,
        })?;

    paths.retain(|path| {
        path.extension()
            .is_some_and(|extension| extension == "json")
    });
    paths.sort();

    paths
        .iter()
        .map(|path| {
            let data = fs::read_to_string(path).map_err(|source| CompatEvidenceError::Read {
                path: path.to_path_buf(),
                source,
            })?;
            serde_json::from_str(&data).map_err(|source| CompatEvidenceError::Json {
                path: path.to_path_buf(),
                source,
            })
        })
        .collect()
}

pub fn validate_source_backing(
    manifest: &CompatibilityManifest,
    evidence: &[EvidenceRecord],
) -> Result<(), CompatEvidenceError> {
    let evidence_backing = evidence_backing(evidence);
    let explicit_backing = explicit_manifest_backing(manifest);

    for fixture in &manifest.fixtures {
        for feature in &manifest.features {
            if !fixture_feature_applies(fixture, feature) {
                continue;
            }

            for lane in &feature.lanes {
                let key = (
                    fixture.fixture_id.clone(),
                    *lane,
                    feature.feature_id.clone(),
                );
                if evidence_backing.contains(&key) || explicit_backing.contains(&key) {
                    continue;
                }

                return Err(CompatEvidenceError::MissingSourceBacking {
                    fixture_id: fixture.fixture_id.clone(),
                    feature_id: feature.feature_id.clone(),
                    lane: *lane,
                });
            }
        }
    }

    Ok(())
}

pub fn artifact_sha256(path: &Path) -> Result<String, CompatEvidenceError> {
    let data = fs::read(path).map_err(|source| CompatEvidenceError::Read {
        path: path.to_path_buf(),
        source,
    })?;
    Ok(hex::encode(Sha256::digest(data)))
}

pub fn merge_manifest(
    existing: Option<CompatibilityManifest>,
    section: &ManifestSection,
) -> CompatibilityManifest {
    let mut manifest = existing.unwrap_or_else(|| empty_manifest(section.schema_version));
    manifest.schema_version = manifest.schema_version.max(section.schema_version);

    manifest
        .fixtures
        .retain(|fixture| !section.owned_fixture_ids.contains(&fixture.fixture_id));
    manifest.fixtures.extend(
        section
            .fixtures
            .iter()
            .filter(|fixture| section.owned_fixture_ids.contains(&fixture.fixture_id))
            .cloned(),
    );

    manifest
        .features
        .retain(|feature| !section.owned_feature_ids.contains(&feature.feature_id));
    manifest.features.extend(
        section
            .features
            .iter()
            .filter(|feature| section.owned_feature_ids.contains(&feature.feature_id))
            .cloned(),
    );

    replace_owned_claims(
        &mut manifest.known_gaps,
        &section.known_gaps,
        &section.owned_fixture_ids,
    );
    replace_owned_claims(
        &mut manifest.non_goals,
        &section.non_goals,
        &section.owned_fixture_ids,
    );
    replace_owned_claims(
        &mut manifest.unsupported,
        &section.unsupported,
        &section.owned_fixture_ids,
    );
    replace_owned_claims(
        &mut manifest.not_observed,
        &section.not_observed,
        &section.owned_fixture_ids,
    );

    manifest.notes.extend(section.notes.clone());
    sort_manifest(&mut manifest);
    manifest
}

pub fn check_manifest_section(
    actual: &CompatibilityManifest,
    expected: &ManifestSection,
) -> Result<(), CompatEvidenceError> {
    let expected_fixtures = owned_fixtures(&expected.fixtures, &expected.owned_fixture_ids);
    let actual_fixtures = owned_fixtures(&actual.fixtures, &expected.owned_fixture_ids);
    if actual_fixtures != expected_fixtures {
        return manifest_section_mismatch(expected, "owned fixtures are stale or missing");
    }

    let expected_features = owned_features(&expected.features, &expected.owned_feature_ids);
    let actual_features = owned_features(&actual.features, &expected.owned_feature_ids);
    if actual_features != expected_features {
        return manifest_section_mismatch(expected, "owned features are stale or missing");
    }

    check_owned_claims(
        expected,
        "known_gaps",
        &actual.known_gaps,
        &expected.known_gaps,
    )?;
    check_owned_claims(
        expected,
        "non_goals",
        &actual.non_goals,
        &expected.non_goals,
    )?;
    check_owned_claims(
        expected,
        "unsupported",
        &actual.unsupported,
        &expected.unsupported,
    )?;
    check_owned_claims(
        expected,
        "not_observed",
        &actual.not_observed,
        &expected.not_observed,
    )?;

    Ok(())
}

pub fn render_matrix_from_paths(
    manifest_path: &Path,
    evidence_dir: &Path,
) -> Result<String, CompatEvidenceError> {
    let manifest = load_manifest(manifest_path)?;
    let evidence = load_evidence_dir(evidence_dir)?;

    validate_source_backing(&manifest, &evidence)?;

    Ok(render_matrix(&manifest, &evidence))
}

fn render_matrix(manifest: &CompatibilityManifest, evidence: &[EvidenceRecord]) -> String {
    let evidence_claims = index_evidence_claims(evidence);
    let manifest_claims = index_manifest_claims(manifest);
    let fixtures: BTreeMap<&str, &FixtureMetadata> = manifest
        .fixtures
        .iter()
        .map(|fixture| (fixture.fixture_id.as_str(), fixture))
        .collect();
    let mut output = String::new();

    output.push_str(
        "<!-- GENERATED by scripts/generate_compat_matrix.sh --write; DO NOT EDIT BY HAND. -->\n",
    );
    output.push_str("# Compatibility Matrix\n\n");
    output.push_str("This matrix is generated from `fixtures/compat/manifest.json` and `fixtures/compat/evidence/*.json`. KeePassXC, optional KeePass, ManyKee read, and ManyKee write lanes are separate evidence sources.\n\n");
    output.push_str("| Feature | Fixture metadata | KeePassXC 2.7.12 | Optional KeePass | ManyKee read | ManyKee write | Evidence | Known gaps / non-goals |\n");
    output.push_str("| --- | --- | --- | --- | --- | --- | --- | --- |\n");

    for fixture in &manifest.fixtures {
        let mut features: Vec<&FeatureRow> = manifest.features.iter().collect();
        features.sort_by(|left, right| {
            feature_order(manifest, left)
                .cmp(&feature_order(manifest, right))
                .then_with(|| left.feature_id.cmp(&right.feature_id))
        });

        for feature in features {
            let feature_applies = fixture_feature_applies(fixture, feature);
            let mut row_sources = BTreeSet::new();
            let mut row_notes = BTreeSet::new();
            let mut lane_cells = Vec::new();

            for lane in lane_order() {
                if !feature_applies || !feature.lanes.contains(&lane) {
                    lane_cells.push("not_applicable".to_string());
                    continue;
                }

                let key = (
                    fixture.fixture_id.as_str(),
                    lane,
                    feature.feature_id.as_str(),
                );
                let evidence_sources = evidence_claims.get(&key).cloned().unwrap_or_default();
                let manifest_sources = manifest_claims.get(&key).cloned().unwrap_or_default();

                for source in evidence_sources.iter().chain(manifest_sources.iter()) {
                    row_sources.insert(source.source_label());
                    for note in &source.notes {
                        row_notes.insert(format!("{}: {}", status_label(source.status), note));
                    }
                }

                lane_cells.push(render_lane_cell(&evidence_sources, &manifest_sources));
            }

            let feature_cell = format!(
                "**{}**<br>`{}`<br>{}",
                feature.name, feature.feature_id, feature.description
            );
            let fixture_cell = render_fixture_cell(&fixtures, &fixture.fixture_id);
            let evidence_cell = if !feature_applies || feature.lanes.is_empty() {
                "not_applicable".to_string()
            } else if row_sources.is_empty() {
                "missing source".to_string()
            } else {
                row_sources.into_iter().collect::<Vec<_>>().join("<br>")
            };
            let notes_cell = render_notes_cell(feature, row_notes);

            output.push_str("| ");
            output.push_str(
                &[
                    feature_cell,
                    fixture_cell,
                    lane_cells[0].clone(),
                    lane_cells[1].clone(),
                    lane_cells[2].clone(),
                    lane_cells[3].clone(),
                    evidence_cell,
                    notes_cell,
                ]
                .into_iter()
                .map(|cell| escape_markdown_cell(&cell))
                .collect::<Vec<_>>()
                .join(" | "),
            );
            output.push_str(" |\n");
        }
    }

    output
}

fn evidence_backing(evidence: &[EvidenceRecord]) -> BTreeSet<(String, EvidenceLane, String)> {
    evidence
        .iter()
        .flat_map(|record| {
            record.claims.iter().map(|claim| {
                (
                    claim
                        .fixture_id
                        .clone()
                        .unwrap_or_else(|| record.fixture_id.clone()),
                    claim.lane.unwrap_or(record.lane),
                    claim.feature_id.clone(),
                )
            })
        })
        .collect()
}

fn explicit_manifest_backing(
    manifest: &CompatibilityManifest,
) -> BTreeSet<(String, EvidenceLane, String)> {
    let mut backing = BTreeSet::new();
    let fixture_ids: Vec<&str> = manifest
        .fixtures
        .iter()
        .map(|fixture| fixture.fixture_id.as_str())
        .collect();
    let feature_lanes: BTreeMap<&str, Vec<EvidenceLane>> = manifest
        .features
        .iter()
        .map(|feature| (feature.feature_id.as_str(), feature.lanes.clone()))
        .collect();

    for claim in manifest
        .known_gaps
        .iter()
        .chain(manifest.non_goals.iter())
        .chain(manifest.unsupported.iter())
        .chain(manifest.not_observed.iter())
    {
        let fixtures: Vec<&str> = match claim.fixture_id.as_deref() {
            Some(fixture_id) => vec![fixture_id],
            None => fixture_ids.clone(),
        };
        let lanes = match claim.lane {
            Some(lane) => vec![lane],
            None => feature_lanes
                .get(claim.feature_id.as_str())
                .cloned()
                .unwrap_or_default(),
        };

        for fixture_id in fixtures {
            for lane in &lanes {
                backing.insert((fixture_id.to_string(), *lane, claim.feature_id.clone()));
            }
        }
    }

    backing
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
struct MatrixSource {
    status: SupportStatus,
    evidence_id: Option<String>,
    evidence_path: Option<String>,
    source: String,
    notes: Vec<String>,
}

impl MatrixSource {
    fn source_label(&self) -> String {
        match (&self.evidence_id, &self.evidence_path) {
            (Some(evidence_id), Some(path)) => {
                format!("[{}]({})", evidence_id, docs_relative_link(path))
            }
            (Some(evidence_id), None) => evidence_id.clone(),
            (None, Some(path)) => format!("{} ({})", self.source, docs_relative_link(path)),
            (None, None) => self.source.clone(),
        }
    }
}

fn index_evidence_claims(
    evidence: &[EvidenceRecord],
) -> BTreeMap<(&str, EvidenceLane, &str), Vec<MatrixSource>> {
    let mut index: BTreeMap<(&str, EvidenceLane, &str), Vec<MatrixSource>> = BTreeMap::new();

    for record in evidence {
        for claim in &record.claims {
            let fixture_id = claim.fixture_id.as_deref().unwrap_or(&record.fixture_id);
            let lane = claim.lane.unwrap_or(record.lane);
            let evidence_path = claim
                .evidence_path
                .clone()
                .or_else(|| record.evidence_path.clone());
            index
                .entry((fixture_id, lane, claim.feature_id.as_str()))
                .or_default()
                .push(MatrixSource {
                    status: claim.status,
                    evidence_id: Some(record.evidence_id.clone()),
                    evidence_path,
                    source: format!("{} {}", record.tool_name, record.tool_version),
                    notes: claim.notes.clone(),
                });
        }
    }

    for sources in index.values_mut() {
        sources.sort();
        sources.dedup();
    }

    index
}

fn index_manifest_claims(
    manifest: &CompatibilityManifest,
) -> BTreeMap<(&str, EvidenceLane, &str), Vec<MatrixSource>> {
    let fixture_ids: Vec<&str> = manifest
        .fixtures
        .iter()
        .map(|fixture| fixture.fixture_id.as_str())
        .collect();
    let feature_lanes: BTreeMap<&str, Vec<EvidenceLane>> = manifest
        .features
        .iter()
        .map(|feature| (feature.feature_id.as_str(), feature.lanes.clone()))
        .collect();
    let mut index: BTreeMap<(&str, EvidenceLane, &str), Vec<MatrixSource>> = BTreeMap::new();

    for (source, claims) in [
        ("manifest known_gaps", &manifest.known_gaps),
        ("manifest non_goals", &manifest.non_goals),
        ("manifest unsupported", &manifest.unsupported),
        ("manifest not_observed", &manifest.not_observed),
    ] {
        for claim in claims {
            let fixtures: Vec<&str> = claim
                .fixture_id
                .as_deref()
                .map(|fixture_id| vec![fixture_id])
                .unwrap_or_else(|| fixture_ids.clone());
            let lanes = claim.lane.map(|lane| vec![lane]).unwrap_or_else(|| {
                feature_lanes
                    .get(claim.feature_id.as_str())
                    .cloned()
                    .unwrap_or_default()
            });

            for fixture_id in fixtures {
                for lane in &lanes {
                    index
                        .entry((fixture_id, *lane, claim.feature_id.as_str()))
                        .or_default()
                        .push(MatrixSource {
                            status: claim.status,
                            evidence_id: None,
                            evidence_path: claim.evidence_path.clone(),
                            source: source.to_string(),
                            notes: claim.notes.clone(),
                        });
                }
            }
        }
    }

    for sources in index.values_mut() {
        sources.sort();
        sources.dedup();
    }

    index
}

fn render_lane_cell(
    evidence_sources: &[MatrixSource],
    manifest_sources: &[MatrixSource],
) -> String {
    let mut parts = Vec::new();

    for source in evidence_sources {
        parts.push(format!(
            "{} ({})",
            status_label(source.status),
            source.source_label()
        ));
    }

    for source in manifest_sources {
        parts.push(format!(
            "{} ({})",
            status_label(source.status),
            source.source_label()
        ));
    }

    if parts.is_empty() {
        "missing source".to_string()
    } else {
        parts.sort();
        parts.dedup();
        parts.join("<br>")
    }
}

fn render_fixture_cell(fixtures: &BTreeMap<&str, &FixtureMetadata>, fixture_id: &str) -> String {
    let Some(fixture) = fixtures.get(fixture_id) else {
        return format!("`{fixture_id}`");
    };

    let mut parts = vec![
        format!("`{}`", fixture.fixture_id),
        format!("`{}`", fixture.source_path),
        fixture.provenance.clone(),
    ];
    if has_expanded_fixture_metadata(fixture) {
        parts.push(format!(
            "source: {} {}",
            empty_label(&fixture.source_tool),
            empty_label(&fixture.source_version)
        ));
        parts.push(format!("status: {}", status_label(fixture.support_status)));
        parts.push(format!("credential: {}", fixture.credential_ref));
        parts.push(format!(
            "generation: {} (stdin lines: {}, manual steps: {}, notes: {})",
            empty_label(&fixture.generation.kind),
            fixture.generation.stdin.len(),
            fixture.generation.manual_steps.len(),
            fixture.generation.notes.len()
        ));
        parts.push(format!(
            "expected assertions: {}",
            fixture.expected_assertions.len()
        ));
        parts.extend(fixture.artifacts.iter().map(|artifact| {
            format!(
                "artifact: `{}` ({}, sha256 `{}`)",
                artifact.path,
                artifact.kind,
                hash_prefix(&artifact.sha256)
            )
        }));
    }
    parts.extend(fixture.notes.clone());
    parts.join("<br>")
}

fn render_notes_cell(feature: &FeatureRow, notes: BTreeSet<String>) -> String {
    let mut parts = Vec::new();
    parts.extend(feature.notes.clone());
    parts.extend(notes);

    if parts.is_empty() {
        "None".to_string()
    } else {
        parts.join("<br>")
    }
}

fn feature_order(manifest: &CompatibilityManifest, feature: &FeatureRow) -> usize {
    manifest
        .features
        .iter()
        .position(|candidate| candidate.feature_id == feature.feature_id)
        .unwrap_or(usize::MAX)
}

fn lane_order() -> [EvidenceLane; 4] {
    [
        EvidenceLane::KeepassXc,
        EvidenceLane::KeepassOptional,
        EvidenceLane::ManyKeeRead,
        EvidenceLane::ManyKeeWrite,
    ]
}

fn status_label(status: SupportStatus) -> &'static str {
    match status {
        SupportStatus::Supported => "supported",
        SupportStatus::Partial => "partial",
        SupportStatus::Unsupported => "unsupported",
        SupportStatus::NotObserved => "not_observed",
        SupportStatus::KnownGap => "known_gap",
        SupportStatus::NonGoal => "non_goal",
        SupportStatus::Manual => "manual",
        SupportStatus::ManualPending => "manual_pending",
    }
}

fn empty_manifest(schema_version: u32) -> CompatibilityManifest {
    CompatibilityManifest {
        schema_version,
        fixtures: Vec::new(),
        features: Vec::new(),
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        unsupported: Vec::new(),
        not_observed: Vec::new(),
        notes: Vec::new(),
    }
}

fn replace_owned_claims(
    actual: &mut Vec<FeatureClaim>,
    expected: &[FeatureClaim],
    owned_fixture_ids: &BTreeSet<String>,
) {
    actual.retain(|claim| !claim_owned_by_fixture(claim, owned_fixture_ids));
    actual.extend(
        expected
            .iter()
            .filter(|claim| claim_owned_by_fixture(claim, owned_fixture_ids))
            .cloned(),
    );
}

fn check_owned_claims(
    section: &ManifestSection,
    claim_kind: &str,
    actual: &[FeatureClaim],
    expected: &[FeatureClaim],
) -> Result<(), CompatEvidenceError> {
    let actual_claims = owned_claims(actual, &section.owned_fixture_ids);
    let expected_claims = owned_claims(expected, &section.owned_fixture_ids);
    if actual_claims != expected_claims {
        return manifest_section_mismatch(
            section,
            &format!("owned {claim_kind} claims are stale or missing"),
        );
    }

    Ok(())
}

fn owned_fixtures(
    fixtures: &[FixtureMetadata],
    owned_fixture_ids: &BTreeSet<String>,
) -> Vec<FixtureMetadata> {
    let mut fixtures: Vec<FixtureMetadata> = fixtures
        .iter()
        .filter(|fixture| owned_fixture_ids.contains(&fixture.fixture_id))
        .cloned()
        .collect();
    fixtures.sort_by(|left, right| left.fixture_id.cmp(&right.fixture_id));
    fixtures
}

fn owned_features(features: &[FeatureRow], owned_feature_ids: &BTreeSet<String>) -> Vec<FeatureRow> {
    let mut features: Vec<FeatureRow> = features
        .iter()
        .filter(|feature| owned_feature_ids.contains(&feature.feature_id))
        .cloned()
        .collect();
    features.sort_by(|left, right| left.feature_id.cmp(&right.feature_id));
    features
}

fn owned_claims(claims: &[FeatureClaim], owned_fixture_ids: &BTreeSet<String>) -> Vec<FeatureClaim> {
    let mut claims: Vec<FeatureClaim> = claims
        .iter()
        .filter(|claim| claim_owned_by_fixture(claim, owned_fixture_ids))
        .cloned()
        .collect();
    sort_claims(&mut claims);
    claims
}

fn claim_owned_by_fixture(claim: &FeatureClaim, owned_fixture_ids: &BTreeSet<String>) -> bool {
    claim
        .fixture_id
        .as_ref()
        .is_some_and(|fixture_id| owned_fixture_ids.contains(fixture_id))
}

fn sort_manifest(manifest: &mut CompatibilityManifest) {
    manifest
        .fixtures
        .sort_by(|left, right| left.fixture_id.cmp(&right.fixture_id));
    manifest
        .features
        .sort_by(|left, right| left.feature_id.cmp(&right.feature_id));
    sort_claims(&mut manifest.known_gaps);
    sort_claims(&mut manifest.non_goals);
    sort_claims(&mut manifest.unsupported);
    sort_claims(&mut manifest.not_observed);
    manifest.notes.sort();
    manifest.notes.dedup();
}

fn sort_claims(claims: &mut Vec<FeatureClaim>) {
    claims.sort_by(|left, right| {
        claim_sort_key(left)
            .cmp(&claim_sort_key(right))
            .then_with(|| left.notes.cmp(&right.notes))
    });
    claims.dedup();
}

fn claim_sort_key(claim: &FeatureClaim) -> (String, String, String, String, String) {
    (
        claim.feature_id.clone(),
        claim.fixture_id.clone().unwrap_or_default(),
        claim
            .lane
            .map(|lane| format!("{lane:?}"))
            .unwrap_or_default(),
        status_label(claim.status).to_string(),
        claim.evidence_path.clone().unwrap_or_default(),
    )
}

fn manifest_section_mismatch<T>(
    section: &ManifestSection,
    reason: &str,
) -> Result<T, CompatEvidenceError> {
    Err(CompatEvidenceError::ManifestSectionMismatch {
        section_id: section.section_id.clone(),
        reason: reason.to_string(),
    })
}

fn fixture_feature_applies(fixture: &FixtureMetadata, feature: &FeatureRow) -> bool {
    fixture.feature_ids.is_empty()
        || fixture
            .feature_ids
            .iter()
            .any(|feature_id| feature_id == &feature.feature_id)
}

fn empty_label(value: &str) -> &str {
    if value.is_empty() {
        "unknown"
    } else {
        value
    }
}

fn hash_prefix(hash: &str) -> &str {
    let len = hash.len().min(12);
    &hash[..len]
}

fn has_expanded_fixture_metadata(fixture: &FixtureMetadata) -> bool {
    !fixture.source_tool.is_empty()
        || !fixture.source_version.is_empty()
        || !fixture.feature_ids.is_empty()
        || !fixture.artifacts.is_empty()
        || fixture.generation != FixtureGeneration::default()
        || !fixture.expected_assertions.is_empty()
        || fixture.support_status != SupportStatus::NotObserved
}

fn docs_relative_link(path: &str) -> String {
    if path.starts_with("http://") || path.starts_with("https://") || path.starts_with("../") {
        path.to_string()
    } else {
        format!("../{path}")
    }
}

fn escape_markdown_cell(cell: &str) -> String {
    cell.replace('|', "\\|").replace('\n', "<br>")
}
