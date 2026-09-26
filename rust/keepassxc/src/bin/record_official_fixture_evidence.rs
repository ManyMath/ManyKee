use keepassxc::compat_evidence::{
    artifact_sha256, check_manifest_section, load_evidence_dir, load_manifest, merge_manifest,
    validate_source_backing, EvidenceLane, EvidenceRecord, FeatureClaim, FeatureRow,
    FixtureArtifact, FixtureGeneration, FixtureMetadata, ManifestSection, SupportStatus,
};
use serde::Serialize;
use std::collections::BTreeSet;
use std::env;
use std::ffi::OsString;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process;
use std::process::{Command, ExitStatus, Stdio};

const REQUIRED_KEEPASSXC_VERSION: &str = "2.7.12";
const ENV_KEEPASSXC_CLI: &str = "MANYKEE_KEEPASSXC_CLI";
const SECTION_ID: &str = "official-keepassxc-2.7.12";
const MANIFEST_PATH: &str = "fixtures/compat/manifest.json";
const EVIDENCE_DIR: &str = "fixtures/compat/evidence";
const OFFICIAL_DIR: &str = "fixtures/compat/official/keepassxc/2.7.12";
const MANUAL_DIR: &str = "fixtures/compat/official/keepassxc/2.7.12/manual";
const MANUAL_README_PATH: &str = "fixtures/compat/official/keepassxc/2.7.12/manual/README.md";
const SOURCES_DIR: &str = "fixtures/compat/sources/keepassxc/2.7.12";
const ATTACHMENT_TEXT_PATH: &str = "fixtures/compat/sources/keepassxc/2.7.12/attachment-text.txt";
const ATTACHMENT_BINARY_PATH: &str =
    "fixtures/compat/sources/keepassxc/2.7.12/attachment-binary.bin";
const MANUAL_CIPHER_KDF_EVIDENCE: &str =
    "fixtures/compat/evidence/keepassxc-manual-pending-cipher-kdf.json";
const UNKNOWN_XML_MANUAL_EVIDENCE: &str =
    "fixtures/compat/evidence/keepassxc-unknownxml-manual-pending.json";
const KEEPASS_OPTIONAL_NOT_OBSERVED_EVIDENCE: &str =
    "fixtures/compat/evidence/keepass-optional-cipher-kdf-not-observed.json";
const FIXTURE_PASSWORD: &str = "manykee-fixture-password";
const ENTRY_PASSWORD: &str = "manykee-entry-password";
const UPDATED_ENTRY_PASSWORD: &str = "manykee-entry-password-edited";
const RICH_PROTECTED_VALUE: &str = "manykee-rich-protected-value";
const TOTP_URI: &str = "otpauth://totp/ManyKee:fixture?secret=JBSWY3DPEHPK3PXP&issuer=ManyKee";

type DynError = Box<dyn std::error::Error>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Write,
    Check,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CredentialKind {
    PasswordOnly,
    KeyFileOnly,
    PasswordAndKeyFile,
}

#[derive(Debug, Clone, Copy)]
struct FixtureDefinition {
    fixture_id: &'static str,
    database_path: &'static str,
    key_file_path: Option<&'static str>,
    extra_artifacts: &'static [(&'static str, &'static str)],
    credential_kind: CredentialKind,
    generation_command: &'static str,
    generation_stdin: &'static [&'static str],
    feature_ids: &'static [&'static str],
    expected_assertions: &'static [&'static str],
    notes: &'static [&'static str],
}

#[derive(Debug, Clone, Copy)]
struct ManualFixtureDefinition {
    fixture_id: &'static str,
    source_path: &'static str,
    source_tool: &'static str,
    source_version: &'static str,
    feature_ids: &'static [&'static str],
    expected_assertions: &'static [&'static str],
    notes: &'static [&'static str],
}

#[derive(Debug, Clone, Copy)]
struct AttachmentSource {
    attachment_name: &'static str,
    relative_path: &'static str,
    contents: &'static [u8],
}

struct GeneratedArtifact {
    relative_path: String,
    contents: String,
}

struct GeneratedEvidence {
    manifest_section: ManifestSection,
    evidence: Vec<GeneratedArtifact>,
}

#[derive(Clone, Debug)]
struct OfficialTool {
    path: PathBuf,
}

#[derive(Debug)]
struct RedactedOutput {
    status: ExitStatus,
    stdout: String,
    stderr: String,
}

fn main() {
    let mode = match parse_mode() {
        Ok(mode) => mode,
        Err(message) => {
            eprintln!("{message}");
            eprintln!("usage: record_official_fixture_evidence (--write|--check)");
            process::exit(2);
        }
    };

    if let Err(err) = run(mode) {
        eprintln!("{err}");
        process::exit(1);
    }
}

fn parse_mode() -> Result<Mode, String> {
    let args: Vec<String> = env::args().skip(1).collect();
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

    match mode {
        Mode::Write => {
            let tool = discover_required_keepassxc()?;
            write_official_artifacts(&project_root, &tool)?;
            let generated = generate_evidence(&project_root)?;
            write_generated(&project_root, &generated)?;
        }
        Mode::Check => {
            let generated = generate_evidence(&project_root)?;
            check_generated(&project_root, &generated)?;
        }
    }

    Ok(())
}

fn write_official_artifacts(project_root: &Path, tool: &OfficialTool) -> Result<(), DynError> {
    fs::create_dir_all(project_root.join(OFFICIAL_DIR))?;
    for definition in fixture_definitions() {
        if definition_artifacts_exist(project_root, &definition) {
            continue;
        }

        remove_definition_artifacts(project_root, &definition)?;
        match definition.fixture_id {
            "keepassxc-password-basic" => {
                write_password_basic_fixture(project_root, tool, &definition)?
            }
            "keepassxc-keyfile-basic" => {
                write_keyfile_basic_fixture(project_root, tool, &definition)?
            }
            "keepassxc-password-keyfile" => {
                write_password_keyfile_fixture(project_root, tool, &definition)?
            }
            "keepassxc-richcontent" => write_richcontent_fixture(project_root, tool, &definition)?,
            "keepassxc-attachments" => write_attachment_fixture(project_root, tool, &definition)?,
            "keepassxc-history-recycle-deleted" => {
                write_history_recycle_fixture(project_root, tool, &definition)?
            }
            fixture_id => {
                return Err(io::Error::other(format!(
                    "missing writer for official fixture {fixture_id}"
                ))
                .into());
            }
        }
    }

    Ok(())
}

fn write_password_basic_fixture(
    project_root: &Path,
    tool: &OfficialTool,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    let mut xml_source = tempfile::NamedTempFile::new()?;
    xml_source.write_all(password_basic_xml().as_bytes())?;
    xml_source.flush()?;

    let args = vec![
        OsString::from("import"),
        OsString::from("-q"),
        OsString::from("-p"),
        xml_source.path().as_os_str().to_os_string(),
        project_root
            .join(definition.database_path)
            .as_os_str()
            .to_os_string(),
    ];
    run_checked_os(
        tool,
        &args,
        &[FIXTURE_PASSWORD, FIXTURE_PASSWORD],
        &secret_redactions(),
    )?;
    Ok(())
}

fn write_keyfile_basic_fixture(
    project_root: &Path,
    tool: &OfficialTool,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    let mut xml_source = tempfile::NamedTempFile::new()?;
    xml_source.write_all(keyfile_basic_xml().as_bytes())?;
    xml_source.flush()?;

    let args = vec![
        OsString::from("import"),
        OsString::from("-q"),
        OsString::from("--set-key-file"),
        project_root
            .join(
                definition
                    .key_file_path
                    .expect("key-file fixture has key path"),
            )
            .as_os_str()
            .to_os_string(),
        xml_source.path().as_os_str().to_os_string(),
        project_root
            .join(definition.database_path)
            .as_os_str()
            .to_os_string(),
    ];
    run_checked_os(tool, &args, &["y"], &secret_redactions())?;
    Ok(())
}

fn write_password_keyfile_fixture(
    project_root: &Path,
    tool: &OfficialTool,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    let mut xml_source = tempfile::NamedTempFile::new()?;
    xml_source.write_all(password_keyfile_xml().as_bytes())?;
    xml_source.flush()?;

    let args = vec![
        OsString::from("import"),
        OsString::from("-q"),
        OsString::from("-p"),
        OsString::from("--set-key-file"),
        project_root
            .join(
                definition
                    .key_file_path
                    .expect("password-plus-key-file fixture has key path"),
            )
            .as_os_str()
            .to_os_string(),
        xml_source.path().as_os_str().to_os_string(),
        project_root
            .join(definition.database_path)
            .as_os_str()
            .to_os_string(),
    ];
    run_checked_os(
        tool,
        &args,
        &[FIXTURE_PASSWORD, FIXTURE_PASSWORD, "y"],
        &secret_redactions(),
    )?;
    Ok(())
}

fn write_richcontent_fixture(
    project_root: &Path,
    tool: &OfficialTool,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    let mut xml_source = tempfile::NamedTempFile::new()?;
    xml_source.write_all(richcontent_xml().as_bytes())?;
    xml_source.flush()?;

    let args = vec![
        OsString::from("import"),
        OsString::from("-q"),
        OsString::from("-p"),
        xml_source.path().as_os_str().to_os_string(),
        project_root
            .join(definition.database_path)
            .as_os_str()
            .to_os_string(),
    ];
    run_checked_os(
        tool,
        &args,
        &[FIXTURE_PASSWORD, FIXTURE_PASSWORD],
        &richcontent_redactions(),
    )?;
    assert_richcontent_export(tool, definition)?;
    Ok(())
}

fn write_attachment_fixture(
    project_root: &Path,
    tool: &OfficialTool,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    write_attachment_sources(project_root)?;

    let mut xml_source = tempfile::NamedTempFile::new()?;
    xml_source.write_all(attachment_fixture_xml().as_bytes())?;
    xml_source.flush()?;

    let args = vec![
        OsString::from("import"),
        OsString::from("-q"),
        OsString::from("-p"),
        xml_source.path().as_os_str().to_os_string(),
        project_root
            .join(definition.database_path)
            .as_os_str()
            .to_os_string(),
    ];
    run_checked_os(
        tool,
        &args,
        &[FIXTURE_PASSWORD, FIXTURE_PASSWORD],
        &secret_redactions(),
    )?;

    for source in attachment_sources() {
        run_checked(
            tool,
            &[
                "attachment-import",
                "-q",
                definition.database_path,
                "Attachments/AttachmentEntry",
                source.attachment_name,
                source.relative_path,
            ],
            &[FIXTURE_PASSWORD],
        )?;
    }
    assert_attachment_export_hashes(project_root, tool, definition)?;
    Ok(())
}

fn write_history_recycle_fixture(
    _project_root: &Path,
    tool: &OfficialTool,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    run_checked(
        tool,
        &["db-create", "-q", "-p", definition.database_path],
        &[FIXTURE_PASSWORD, FIXTURE_PASSWORD],
    )?;
    run_checked(
        tool,
        &[
            "add",
            "-q",
            "-u",
            "history-user",
            "--notes",
            "Initial history note.",
            "-p",
            definition.database_path,
            "HistoryEntry",
        ],
        &[FIXTURE_PASSWORD, ENTRY_PASSWORD],
    )?;
    run_checked(
        tool,
        &[
            "edit",
            "-q",
            "-u",
            "history-user-edited",
            "--notes",
            "Edited history note.",
            "-p",
            definition.database_path,
            "HistoryEntry",
        ],
        &[FIXTURE_PASSWORD, UPDATED_ENTRY_PASSWORD],
    )?;
    run_checked(
        tool,
        &[
            "add",
            "-q",
            "-u",
            "deleted-user",
            "--notes",
            "Entry used to prove recycle bin and DeletedObject metadata.",
            "-p",
            definition.database_path,
            "DeletedEntry",
        ],
        &[FIXTURE_PASSWORD, ENTRY_PASSWORD],
    )?;
    run_checked(
        tool,
        &["rm", "-q", definition.database_path, "DeletedEntry"],
        &[FIXTURE_PASSWORD],
    )?;

    let recycle_path = discover_recycle_entry_path(tool, definition, "DeletedEntry")?;
    run_checked_os(
        tool,
        &[
            OsString::from("rm"),
            OsString::from("-q"),
            project_relative_arg(definition.database_path),
            OsString::from(&recycle_path),
        ],
        &[FIXTURE_PASSWORD],
        &secret_redactions(),
    )?;
    assert_history_recycle_export(tool, definition)?;
    Ok(())
}

fn write_attachment_sources(project_root: &Path) -> Result<(), DynError> {
    fs::create_dir_all(project_root.join(SOURCES_DIR))?;
    for source in attachment_sources() {
        fs::write(project_root.join(source.relative_path), source.contents)?;
    }
    Ok(())
}

fn assert_attachment_export_hashes(
    project_root: &Path,
    tool: &OfficialTool,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    let tempdir = tempfile::tempdir()?;
    for source in attachment_sources() {
        let exported_path = tempdir.path().join(source.attachment_name);
        let args = vec![
            OsString::from("attachment-export"),
            OsString::from("-q"),
            project_relative_arg(definition.database_path),
            OsString::from("Attachments/AttachmentEntry"),
            OsString::from(source.attachment_name),
            exported_path.as_os_str().to_os_string(),
        ];
        run_checked_os(tool, &args, &[FIXTURE_PASSWORD], &secret_redactions())?;

        let source_hash = artifact_sha256(&project_root.join(source.relative_path))?;
        let exported_hash = artifact_sha256(&exported_path)?;
        if source_hash != exported_hash {
            return Err(io::Error::other(format!(
                "attachment-export hash mismatch for {}: source_sha256={} exported_sha256={}",
                source.attachment_name, source_hash, exported_hash
            ))
            .into());
        }
    }
    Ok(())
}

fn discover_recycle_entry_path(
    tool: &OfficialTool,
    definition: &FixtureDefinition,
    entry_name: &str,
) -> Result<String, DynError> {
    let args = vec![
        OsString::from("ls"),
        OsString::from("-q"),
        OsString::from("-R"),
        OsString::from("-f"),
        project_relative_arg(definition.database_path),
    ];
    let output = run_checked_os(tool, &args, &[FIXTURE_PASSWORD], &secret_redactions())?;
    output
        .stdout
        .lines()
        .map(str::trim)
        .find(|line| line.ends_with(entry_name) && line.contains("Recycle"))
        .map(str::to_string)
        .ok_or_else(|| {
            io::Error::other(format!(
                "could not find {entry_name} under recycle group after rm"
            ))
            .into()
        })
}

fn assert_history_recycle_export(
    tool: &OfficialTool,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    let args = vec![
        OsString::from("export"),
        OsString::from("-q"),
        project_relative_arg(definition.database_path),
    ];
    let output = run_checked_os(tool, &args, &[FIXTURE_PASSWORD], &secret_redactions())?;
    for expected in [
        "<History>",
        "<DeletedObject>",
        "HistoryEntry",
        "Recycle Bin",
    ] {
        if !output.stdout.contains(expected) {
            return Err(io::Error::other(format!(
                "history/recycle export missing expected value {expected}"
            ))
            .into());
        }
    }
    Ok(())
}

fn definition_artifacts_exist(project_root: &Path, definition: &FixtureDefinition) -> bool {
    let database_exists = project_root.join(definition.database_path).is_file();
    let key_file_exists = match definition.key_file_path {
        Some(key_file_path) => project_root.join(key_file_path).is_file(),
        None => true,
    };
    let extra_artifacts_exist = definition
        .extra_artifacts
        .iter()
        .all(|(path, _kind)| project_root.join(*path).is_file());
    database_exists && key_file_exists && extra_artifacts_exist
}

fn remove_definition_artifacts(
    project_root: &Path,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    remove_if_exists(project_root.join(definition.database_path))?;
    if let Some(key_file_path) = definition.key_file_path {
        remove_if_exists(project_root.join(key_file_path))?;
    }
    Ok(())
}

fn assert_richcontent_export(
    tool: &OfficialTool,
    definition: &FixtureDefinition,
) -> Result<(), DynError> {
    let args = vec![
        OsString::from("export"),
        OsString::from("-q"),
        project_relative_arg(definition.database_path),
    ];
    let output = run_checked_os(tool, &args, &[FIXTURE_PASSWORD], &richcontent_redactions())?;

    for expected in [
        "StandardEntry",
        "CustomFieldsEntry",
        "ProtectedEntry",
        "TOTPEntry",
        "AutoTypeEntry",
        "manykee-meta-key",
        "manykee-group-key",
        "manykee-entry-key",
        "JBSWY3DPEHPK3PXP",
    ] {
        if !output.stdout.contains(expected) {
            return Err(io::Error::other(format!(
                "rich-content XML export missing expected value {expected}"
            ))
            .into());
        }
    }

    Ok(())
}

fn richcontent_redactions() -> [&'static str; 3] {
    [FIXTURE_PASSWORD, ENTRY_PASSWORD, RICH_PROTECTED_VALUE]
}

fn secret_redactions() -> [&'static str; 4] {
    [
        FIXTURE_PASSWORD,
        ENTRY_PASSWORD,
        UPDATED_ENTRY_PASSWORD,
        RICH_PROTECTED_VALUE,
    ]
}

fn password_basic_xml() -> String {
    r#"<?xml version="1.0" encoding="utf-8"?>
<KeePassFile>
  <Meta>
    <Generator>ManyKee synthetic KeePassXC XML import source</Generator>
    <DatabaseName>keepassxc-password-basic</DatabaseName>
    <DatabaseDescription>Synthetic password-basic source imported by KeePassXC CLI 2.7.12.</DatabaseDescription>
    <MemoryProtection>
      <ProtectTitle>False</ProtectTitle>
      <ProtectUserName>False</ProtectUserName>
      <ProtectPassword>True</ProtectPassword>
      <ProtectURL>False</ProtectURL>
      <ProtectNotes>False</ProtectNotes>
    </MemoryProtection>
  </Meta>
  <Root>
    <Group>
      <UUID>AAAAAAAAAAAAAAAAAAAAEA==</UUID>
      <Name>Root</Name>
      <Times>
        <LastModificationTime>2026-04-16T00:00:00Z</LastModificationTime>
        <CreationTime>2026-04-16T00:00:00Z</CreationTime>
        <LastAccessTime>2026-04-16T00:00:00Z</LastAccessTime>
        <ExpiryTime>2026-04-16T00:00:00Z</ExpiryTime>
        <Expires>False</Expires>
        <UsageCount>0</UsageCount>
        <LocationChanged>2026-04-16T00:00:00Z</LocationChanged>
      </Times>
      <Group>
        <UUID>AAAAAAAAAAAAAAAAAAAAEQ==</UUID>
        <Name>Fixtures</Name>
        <Times>
          <LastModificationTime>2026-04-16T00:00:00Z</LastModificationTime>
          <CreationTime>2026-04-16T00:00:00Z</CreationTime>
          <LastAccessTime>2026-04-16T00:00:00Z</LastAccessTime>
          <ExpiryTime>2026-04-16T00:00:00Z</ExpiryTime>
          <Expires>False</Expires>
          <UsageCount>0</UsageCount>
          <LocationChanged>2026-04-16T00:00:00Z</LocationChanged>
        </Times>
        <CustomData>
          <Item>
            <Key>manykee-basic-kdbx4-marker</Key>
            <Value>present</Value>
          </Item>
        </CustomData>
        <Entry>
          <UUID>AAAAAAAAAAAAAAAAAAAAEg==</UUID>
          <Times>
            <LastModificationTime>2026-04-16T00:00:00Z</LastModificationTime>
            <CreationTime>2026-04-16T00:00:00Z</CreationTime>
            <LastAccessTime>2026-04-16T00:00:00Z</LastAccessTime>
            <ExpiryTime>2026-04-16T00:00:00Z</ExpiryTime>
            <Expires>False</Expires>
            <UsageCount>0</UsageCount>
            <LocationChanged>2026-04-16T00:00:00Z</LocationChanged>
          </Times>
          <String>
            <Key>Title</Key>
            <Value>BasicEntry</Value>
          </String>
          <String>
            <Key>UserName</Key>
            <Value>fixture-user</Value>
          </String>
          <String>
            <Key>Password</Key>
            <Value>manykee-entry-password</Value>
          </String>
          <String>
            <Key>URL</Key>
            <Value>https://manykee.test/basic</Value>
          </String>
          <String>
            <Key>Notes</Key>
            <Value>Synthetic basic entry</Value>
          </String>
        </Entry>
      </Group>
    </Group>
  </Root>
</KeePassFile>
"#
    .to_string()
}

fn keyfile_basic_xml() -> String {
    r#"<?xml version="1.0" encoding="utf-8"?>
<KeePassFile>
  <Meta>
    <Generator>ManyKee synthetic KeePassXC XML import source</Generator>
    <DatabaseName>keepassxc-keyfile-basic</DatabaseName>
    <DatabaseDescription>Synthetic keyfile-basic source imported by KeePassXC CLI 2.7.12.</DatabaseDescription>
    <MemoryProtection>
      <ProtectTitle>False</ProtectTitle>
      <ProtectUserName>False</ProtectUserName>
      <ProtectPassword>True</ProtectPassword>
      <ProtectURL>False</ProtectURL>
      <ProtectNotes>False</ProtectNotes>
    </MemoryProtection>
  </Meta>
  <Root>
    <Group>
      <UUID>AAAAAAAAAAAAAAAAAAAAIA==</UUID>
      <Name>Root</Name>
      <Times>
        <LastModificationTime>2026-04-16T00:00:00Z</LastModificationTime>
        <CreationTime>2026-04-16T00:00:00Z</CreationTime>
        <LastAccessTime>2026-04-16T00:00:00Z</LastAccessTime>
        <ExpiryTime>2026-04-16T00:00:00Z</ExpiryTime>
        <Expires>False</Expires>
        <UsageCount>0</UsageCount>
        <LocationChanged>2026-04-16T00:00:00Z</LocationChanged>
      </Times>
      <CustomData>
        <Item>
          <Key>manykee-keyfile-kdbx4-marker</Key>
          <Value>present</Value>
        </Item>
      </CustomData>
    </Group>
  </Root>
</KeePassFile>
"#
    .to_string()
}

fn password_keyfile_xml() -> String {
    r#"<?xml version="1.0" encoding="utf-8"?>
<KeePassFile>
  <Meta>
    <Generator>ManyKee synthetic KeePassXC XML import source</Generator>
    <DatabaseName>keepassxc-password-keyfile</DatabaseName>
    <DatabaseDescription>Synthetic password-keyfile source imported by KeePassXC CLI 2.7.12.</DatabaseDescription>
    <MemoryProtection>
      <ProtectTitle>False</ProtectTitle>
      <ProtectUserName>False</ProtectUserName>
      <ProtectPassword>True</ProtectPassword>
      <ProtectURL>False</ProtectURL>
      <ProtectNotes>False</ProtectNotes>
    </MemoryProtection>
  </Meta>
  <Root>
    <Group>
      <UUID>AAAAAAAAAAAAAAAAAAAAMA==</UUID>
      <Name>Root</Name>
      <Times>
        <LastModificationTime>2026-04-16T00:00:00Z</LastModificationTime>
        <CreationTime>2026-04-16T00:00:00Z</CreationTime>
        <LastAccessTime>2026-04-16T00:00:00Z</LastAccessTime>
        <ExpiryTime>2026-04-16T00:00:00Z</ExpiryTime>
        <Expires>False</Expires>
        <UsageCount>0</UsageCount>
        <LocationChanged>2026-04-16T00:00:00Z</LocationChanged>
      </Times>
      <CustomData>
        <Item>
          <Key>manykee-password-keyfile-kdbx4-marker</Key>
          <Value>present</Value>
        </Item>
      </CustomData>
    </Group>
  </Root>
</KeePassFile>
"#
    .to_string()
}

fn attachment_fixture_xml() -> String {
    r#"<?xml version="1.0" encoding="utf-8"?>
<KeePassFile>
  <Meta>
    <Generator>ManyKee synthetic KeePassXC XML import source</Generator>
    <DatabaseName>keepassxc-attachments</DatabaseName>
    <DatabaseDescription>Synthetic attachment source imported by KeePassXC CLI 2.7.12.</DatabaseDescription>
    <MemoryProtection>
      <ProtectTitle>False</ProtectTitle>
      <ProtectUserName>False</ProtectUserName>
      <ProtectPassword>True</ProtectPassword>
      <ProtectURL>False</ProtectURL>
      <ProtectNotes>False</ProtectNotes>
    </MemoryProtection>
  </Meta>
  <Root>
    <Group>
      <UUID>AAAAAAAAAAAAAAAAAAAAQA==</UUID>
      <Name>Root</Name>
      <Times>
        <LastModificationTime>2026-04-16T00:00:00Z</LastModificationTime>
        <CreationTime>2026-04-16T00:00:00Z</CreationTime>
        <LastAccessTime>2026-04-16T00:00:00Z</LastAccessTime>
        <ExpiryTime>2026-04-16T00:00:00Z</ExpiryTime>
        <Expires>False</Expires>
        <UsageCount>0</UsageCount>
        <LocationChanged>2026-04-16T00:00:00Z</LocationChanged>
      </Times>
      <Group>
        <UUID>AAAAAAAAAAAAAAAAAAAAQQ==</UUID>
        <Name>Attachments</Name>
        <Times>
          <LastModificationTime>2026-04-16T00:00:00Z</LastModificationTime>
          <CreationTime>2026-04-16T00:00:00Z</CreationTime>
          <LastAccessTime>2026-04-16T00:00:00Z</LastAccessTime>
          <ExpiryTime>2026-04-16T00:00:00Z</ExpiryTime>
          <Expires>False</Expires>
          <UsageCount>0</UsageCount>
          <LocationChanged>2026-04-16T00:00:00Z</LocationChanged>
        </Times>
        <CustomData>
          <Item>
            <Key>manykee-attachments-kdbx4-marker</Key>
            <Value>present</Value>
          </Item>
        </CustomData>
        <Entry>
          <UUID>AAAAAAAAAAAAAAAAAAAAQg==</UUID>
          <Times>
            <LastModificationTime>2026-04-16T00:00:00Z</LastModificationTime>
            <CreationTime>2026-04-16T00:00:00Z</CreationTime>
            <LastAccessTime>2026-04-16T00:00:00Z</LastAccessTime>
            <ExpiryTime>2026-04-16T00:00:00Z</ExpiryTime>
            <Expires>False</Expires>
            <UsageCount>0</UsageCount>
            <LocationChanged>2026-04-16T00:00:00Z</LocationChanged>
          </Times>
          <String>
            <Key>Title</Key>
            <Value>AttachmentEntry</Value>
          </String>
          <String>
            <Key>UserName</Key>
            <Value>attachment-user</Value>
          </String>
          <String>
            <Key>Password</Key>
            <Value>manykee-entry-password</Value>
          </String>
          <String>
            <Key>Notes</Key>
            <Value>Synthetic entry containing text and binary attachments.</Value>
          </String>
        </Entry>
      </Group>
    </Group>
  </Root>
</KeePassFile>
"#
    .to_string()
}

fn attachment_sources() -> [AttachmentSource; 2] {
    [
        AttachmentSource {
            attachment_name: "sample.txt",
            relative_path: ATTACHMENT_TEXT_PATH,
            contents: b"ManyKee KeePassXC attachment text fixture.\nLine two proves newline preservation.\n",
        },
        AttachmentSource {
            attachment_name: "sample.bin",
            relative_path: ATTACHMENT_BINARY_PATH,
            contents: &[
                0x00, 0x01, 0x02, 0x03, 0x10, 0x20, 0x7f, 0x80, 0xfe, 0xff, b'M', b'K',
                b'X', b'C',
            ],
        },
    ]
}

fn richcontent_xml() -> String {
    format!(
        r#"<?xml version="1.0" encoding="utf-8"?>
<KeePassFile>
  <Meta>
    <Generator>ManyKee synthetic KeePassXC XML import source</Generator>
    <DatabaseName>ManyKee Official Rich Content Fixture</DatabaseName>
    <DatabaseDescription>Synthetic rich-content source imported by KeePassXC CLI 2.7.12.</DatabaseDescription>
    <DefaultUserName>fixture-default-user</DefaultUserName>
    <MemoryProtection>
      <ProtectTitle>False</ProtectTitle>
      <ProtectUserName>False</ProtectUserName>
      <ProtectPassword>True</ProtectPassword>
      <ProtectURL>False</ProtectURL>
      <ProtectNotes>False</ProtectNotes>
    </MemoryProtection>
    <CustomData>
      <Item>
        <Key>manykee-meta-key</Key>
        <Value>manykee-meta-value</Value>
      </Item>
    </CustomData>
  </Meta>
  <Root>
    <Group>
      <UUID>AAAAAAAAAAAAAAAAAAAAAQ==</UUID>
      <Name>Root</Name>
      <Times>
        <LastModificationTime>2026-04-15T00:00:00Z</LastModificationTime>
        <CreationTime>2026-04-15T00:00:00Z</CreationTime>
        <LastAccessTime>2026-04-15T00:00:00Z</LastAccessTime>
        <ExpiryTime>2026-04-15T00:00:00Z</ExpiryTime>
        <Expires>False</Expires>
        <UsageCount>0</UsageCount>
        <LocationChanged>2026-04-15T00:00:00Z</LocationChanged>
      </Times>
      <Notes>Synthetic XML import root group.</Notes>
      <Group>
        <UUID>AAAAAAAAAAAAAAAAAAAAAg==</UUID>
        <Name>Fixtures</Name>
        <Times>
          <LastModificationTime>2026-04-15T00:00:00Z</LastModificationTime>
          <CreationTime>2026-04-15T00:00:00Z</CreationTime>
          <LastAccessTime>2026-04-15T00:00:00Z</LastAccessTime>
          <ExpiryTime>2026-04-15T00:00:00Z</ExpiryTime>
          <Expires>False</Expires>
          <UsageCount>0</UsageCount>
          <LocationChanged>2026-04-15T00:00:00Z</LocationChanged>
        </Times>
      <Notes>Top-level synthetic official fixture group.</Notes>
      <Tags>official;richcontent</Tags>
      <CustomData>
        <Item>
          <Key>manykee-group-key</Key>
          <Value>manykee-group-value</Value>
        </Item>
      </CustomData>
      <Group>
        <UUID>AAAAAAAAAAAAAAAAAAAAAw==</UUID>
        <Name>Nested</Name>
        <Times>
          <LastModificationTime>2026-04-15T00:00:00Z</LastModificationTime>
          <CreationTime>2026-04-15T00:00:00Z</CreationTime>
          <LastAccessTime>2026-04-15T00:00:00Z</LastAccessTime>
          <ExpiryTime>2026-04-15T00:00:00Z</ExpiryTime>
          <Expires>False</Expires>
          <UsageCount>0</UsageCount>
          <LocationChanged>2026-04-15T00:00:00Z</LocationChanged>
        </Times>
        <Notes>Nested group imported from XML.</Notes>
        <Entry>
          <UUID>AAAAAAAAAAAAAAAAAAAABA==</UUID>
          <Times>
            <LastModificationTime>2026-04-15T00:00:00Z</LastModificationTime>
            <CreationTime>2026-04-15T00:00:00Z</CreationTime>
            <LastAccessTime>2026-04-15T00:00:00Z</LastAccessTime>
            <ExpiryTime>2026-04-15T00:00:00Z</ExpiryTime>
            <Expires>False</Expires>
            <UsageCount>0</UsageCount>
            <LocationChanged>2026-04-15T00:00:00Z</LocationChanged>
          </Times>
          <String>
            <Key>Title</Key>
            <Value>StandardEntry</Value>
          </String>
          <String>
            <Key>UserName</Key>
            <Value>standard-user</Value>
          </String>
          <String>
            <Key>Password</Key>
            <Value>standard-password</Value>
          </String>
          <String>
            <Key>URL</Key>
            <Value>https://manykee.test/rich/standard</Value>
          </String>
          <String>
            <Key>Notes</Key>
            <Value>Standard fields imported through KeePassXC XML.</Value>
          </String>
          <Tags>official;standard</Tags>
        </Entry>
        <Entry>
          <UUID>AAAAAAAAAAAAAAAAAAAABQ==</UUID>
          <Times>
            <LastModificationTime>2026-04-15T00:00:00Z</LastModificationTime>
            <CreationTime>2026-04-15T00:00:00Z</CreationTime>
            <LastAccessTime>2026-04-15T00:00:00Z</LastAccessTime>
            <ExpiryTime>2026-04-15T00:00:00Z</ExpiryTime>
            <Expires>False</Expires>
            <UsageCount>0</UsageCount>
            <LocationChanged>2026-04-15T00:00:00Z</LocationChanged>
          </Times>
          <String>
            <Key>Title</Key>
            <Value>CustomFieldsEntry</Value>
          </String>
          <String>
            <Key>UserName</Key>
            <Value>custom-user</Value>
          </String>
          <String>
            <Key>Password</Key>
            <Value>custom-password</Value>
          </String>
          <String>
            <Key>manykee-custom-field</Key>
            <Value>custom-field-value</Value>
          </String>
          <CustomData>
            <Item>
              <Key>manykee-entry-key</Key>
              <Value>manykee-entry-value</Value>
            </Item>
          </CustomData>
          <Tags>custom;fields</Tags>
        </Entry>
        <Entry>
          <UUID>AAAAAAAAAAAAAAAAAAAABg==</UUID>
          <Times>
            <LastModificationTime>2026-04-15T00:00:00Z</LastModificationTime>
            <CreationTime>2026-04-15T00:00:00Z</CreationTime>
            <LastAccessTime>2026-04-15T00:00:00Z</LastAccessTime>
            <ExpiryTime>2026-04-15T00:00:00Z</ExpiryTime>
            <Expires>False</Expires>
            <UsageCount>0</UsageCount>
            <LocationChanged>2026-04-15T00:00:00Z</LocationChanged>
          </Times>
          <String>
            <Key>Title</Key>
            <Value>ProtectedEntry</Value>
          </String>
          <String>
            <Key>UserName</Key>
            <Value>protected-user</Value>
          </String>
          <String>
            <Key>Password</Key>
            <Value>{rich_protected_value}</Value>
          </String>
          <Tags>protected</Tags>
        </Entry>
        <Entry>
          <UUID>AAAAAAAAAAAAAAAAAAAABw==</UUID>
          <Times>
            <LastModificationTime>2026-04-15T00:00:00Z</LastModificationTime>
            <CreationTime>2026-04-15T00:00:00Z</CreationTime>
            <LastAccessTime>2026-04-15T00:00:00Z</LastAccessTime>
            <ExpiryTime>2026-04-15T00:00:00Z</ExpiryTime>
            <Expires>False</Expires>
            <UsageCount>0</UsageCount>
            <LocationChanged>2026-04-15T00:00:00Z</LocationChanged>
          </Times>
          <String>
            <Key>Title</Key>
            <Value>TOTPEntry</Value>
          </String>
          <String>
            <Key>UserName</Key>
            <Value>totp-user</Value>
          </String>
          <String>
            <Key>Password</Key>
            <Value>totp-password</Value>
          </String>
          <CustomData>
            <Item>
              <Key>otp</Key>
              <Value>{totp_uri}</Value>
            </Item>
          </CustomData>
          <Tags>totp;customdata</Tags>
        </Entry>
        <Entry>
          <UUID>AAAAAAAAAAAAAAAAAAAACA==</UUID>
          <Times>
            <LastModificationTime>2026-04-15T00:00:00Z</LastModificationTime>
            <CreationTime>2026-04-15T00:00:00Z</CreationTime>
            <LastAccessTime>2026-04-15T00:00:00Z</LastAccessTime>
            <ExpiryTime>2026-04-15T00:00:00Z</ExpiryTime>
            <Expires>False</Expires>
            <UsageCount>0</UsageCount>
            <LocationChanged>2026-04-15T00:00:00Z</LocationChanged>
          </Times>
          <String>
            <Key>Title</Key>
            <Value>AutoTypeEntry</Value>
          </String>
          <String>
            <Key>UserName</Key>
            <Value>autotype-user</Value>
          </String>
          <String>
            <Key>Password</Key>
            <Value>autotype-password</Value>
          </String>
          <AutoType>
            <Enabled>True</Enabled>
            <DataTransferObfuscation>0</DataTransferObfuscation>
            <DefaultSequence>{{USERNAME}}{{TAB}}{{PASSWORD}}{{ENTER}}</DefaultSequence>
            <Association>
              <Window>manykee-richcontent</Window>
              <KeystrokeSequence>{{USERNAME}}{{TAB}}{{PASSWORD}}</KeystrokeSequence>
            </Association>
          </AutoType>
          <Tags>autotype</Tags>
        </Entry>
      </Group>
      </Group>
    </Group>
  </Root>
</KeePassFile>
"#,
        rich_protected_value = RICH_PROTECTED_VALUE,
        totp_uri = TOTP_URI.replace('&', "&amp;"),
    )
}

fn generate_evidence(project_root: &Path) -> Result<GeneratedEvidence, DynError> {
    let manifest_section = build_manifest_section(project_root)?;
    let mut evidence = fixture_definitions()
        .iter()
        .map(|definition| {
            let evidence_path = evidence_path(definition.fixture_id);
            Ok(GeneratedArtifact {
                relative_path: evidence_path.clone(),
                contents: pretty_json(&official_evidence_record(
                    project_root,
                    definition,
                    &evidence_path,
                )?)?,
            })
        })
        .collect::<Result<Vec<_>, DynError>>()?;
    evidence.extend(manual_evidence_artifacts(project_root)?);
    evidence.push(optional_keepass_evidence_artifact()?);
    evidence.push(GeneratedArtifact {
        relative_path: MANUAL_README_PATH.to_string(),
        contents: manual_readme_contents(),
    });

    Ok(GeneratedEvidence {
        manifest_section,
        evidence,
    })
}

fn write_generated(project_root: &Path, generated: &GeneratedEvidence) -> Result<(), DynError> {
    fs::create_dir_all(project_root.join(EVIDENCE_DIR))?;
    write_manifest_section(project_root, &generated.manifest_section)?;
    for artifact in &generated.evidence {
        write_artifact(project_root, artifact)?;
    }
    Ok(())
}

fn check_generated(project_root: &Path, generated: &GeneratedEvidence) -> Result<(), DynError> {
    check_manifest_section_artifact(project_root, &generated.manifest_section)?;
    for artifact in &generated.evidence {
        check_artifact(project_root, artifact)?;
    }

    let mut manifest = load_manifest(&project_root.join(MANIFEST_PATH))?;
    manifest.not_observed.extend(delegated_manykee_claims());
    let evidence = load_evidence_dir(&project_root.join(EVIDENCE_DIR))?;
    validate_source_backing(&manifest, &evidence)?;

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
                "{MANIFEST_PATH} official section is stale; run `cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_official_fixture_evidence -- --write`: {source}"
            ),
        )
    })?;
    Ok(())
}

fn write_artifact(project_root: &Path, artifact: &GeneratedArtifact) -> Result<(), DynError> {
    let path = project_root.join(&artifact.relative_path);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, &artifact.contents)?;
    Ok(())
}

fn check_artifact(project_root: &Path, artifact: &GeneratedArtifact) -> Result<(), DynError> {
    let path = project_root.join(&artifact.relative_path);
    let actual = fs::read_to_string(&path).map_err(|source| {
        io::Error::new(
            source.kind(),
            format!("failed to read {}: {source}", artifact.relative_path),
        )
    })?;

    if actual != artifact.contents {
        return Err(io::Error::other(format!(
                "{} is stale; run `cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_official_fixture_evidence -- --write`",
                artifact.relative_path
            ),
        )
        .into());
    }

    Ok(())
}

fn build_manifest_section(project_root: &Path) -> Result<ManifestSection, DynError> {
    let definitions = fixture_definitions();
    let manual_definitions = manual_fixture_definitions();
    let features = official_features();
    let owned_fixture_ids = definitions
        .iter()
        .map(|definition| definition.fixture_id.to_string())
        .chain(
            manual_definitions
                .iter()
                .map(|definition| definition.fixture_id.to_string()),
        )
        .collect::<BTreeSet<_>>();
    let owned_feature_ids = features
        .iter()
        .map(|feature| feature.feature_id.clone())
        .collect::<BTreeSet<_>>();
    let mut fixtures = definitions
        .iter()
        .map(|definition| fixture_metadata(project_root, definition))
        .collect::<Result<Vec<_>, DynError>>()?;
    fixtures.extend(
        manual_definitions
            .iter()
            .map(|definition| manual_fixture_metadata(project_root, definition))
            .collect::<Result<Vec<_>, DynError>>()?,
    );
    let not_observed = definitions
        .iter()
        .flat_map(|definition| {
            keepass_optional_not_observed_claims(
                definition.fixture_id,
                definition.feature_ids,
                "The official fixture corpus records KeePassXC source evidence only; optional KeePass remains deferred.",
            )
        })
        .chain(manual_definitions.iter().flat_map(|definition| {
            non_keepassxc_not_observed_claims(
                definition.fixture_id,
                definition.feature_ids,
                "Manual KeePassXC capture is pending; optional KeePass and ManyKee parity lanes remain deferred.",
            )
        }))
        .collect();

    Ok(ManifestSection {
        section_id: SECTION_ID.to_string(),
        schema_version: 2,
        owned_fixture_ids,
        owned_feature_ids,
        fixtures,
        features,
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        unsupported: Vec::new(),
        not_observed,
        notes: vec![
            "Official KeePassXC 2.7.12 fixtures are generated by record_official_fixture_evidence; the recorder owns only keepassxc-* fixture IDs.".to_string(),
            "Starter evidence generated by record_compat_evidence is preserved by shared manifest-section merge semantics.".to_string(),
        ],
    })
}

fn fixture_metadata(
    project_root: &Path,
    definition: &FixtureDefinition,
) -> Result<FixtureMetadata, DynError> {
    let mut artifacts = vec![artifact(project_root, definition.database_path, "kdbx")?];
    if let Some(key_file_path) = definition.key_file_path {
        artifacts.push(artifact(project_root, key_file_path, "key-file")?);
    }
    for &(path, kind) in definition.extra_artifacts {
        artifacts.push(artifact(project_root, path, kind)?);
    }

    Ok(FixtureMetadata {
        fixture_id: definition.fixture_id.to_string(),
        source_path: definition.database_path.to_string(),
        credential_ref: credential_ref(definition).to_string(),
        provenance: "Generated by KeePassXC CLI 2.7.12 through stdin-only synthetic credential prompts.".to_string(),
        source_tool: "keepassxc-cli".to_string(),
        source_version: REQUIRED_KEEPASSXC_VERSION.to_string(),
        feature_ids: definition
            .feature_ids
            .iter()
            .map(|feature_id| feature_id.to_string())
            .collect(),
        artifacts,
        generation: FixtureGeneration {
            kind: "cli".to_string(),
            command: Some(definition.generation_command.to_string()),
            stdin: definition
                .generation_stdin
                .iter()
                .map(|line| line.to_string())
                .collect(),
            manual_steps: Vec::new(),
            notes: vec![
                "Recorder passes synthetic fixture secrets through stdin and refuses fixture secrets in argv.".to_string(),
            ],
        },
        expected_assertions: definition
            .expected_assertions
            .iter()
            .map(|assertion| assertion.to_string())
            .collect(),
        support_status: SupportStatus::Supported,
        notes: definition.notes.iter().map(|note| note.to_string()).collect(),
    })
}

fn manual_fixture_metadata(
    project_root: &Path,
    definition: &ManualFixtureDefinition,
) -> Result<FixtureMetadata, DynError> {
    let artifact_path = project_root.join(definition.source_path);
    let artifacts = if artifact_path.is_file() {
        vec![artifact(project_root, definition.source_path, "kdbx")?]
    } else {
        Vec::new()
    };
    let status = if artifacts.is_empty() {
        SupportStatus::ManualPending
    } else {
        SupportStatus::Manual
    };

    Ok(FixtureMetadata {
        fixture_id: definition.fixture_id.to_string(),
        source_path: definition.source_path.to_string(),
        credential_ref: "synthetic password fixture: manykee-fixture-password".to_string(),
        provenance: "KeePassXC GUI/manual fixture capture is pending; no automated support claim is made before provenance-clear artifact capture.".to_string(),
        source_tool: definition.source_tool.to_string(),
        source_version: definition.source_version.to_string(),
        feature_ids: definition
            .feature_ids
            .iter()
            .map(|feature_id| feature_id.to_string())
            .collect(),
        artifacts,
        generation: FixtureGeneration {
            kind: if status == SupportStatus::ManualPending {
                "manual_pending".to_string()
            } else {
                "manual".to_string()
            },
            command: None,
            stdin: Vec::new(),
            manual_steps: manual_steps(definition),
            notes: vec![
                "Manual fixture capture must use synthetic credentials and commit the resulting KDBX before the recorder captures hashes.".to_string(),
            ],
        },
        expected_assertions: definition
            .expected_assertions
            .iter()
            .map(|assertion| assertion.to_string())
            .collect(),
        support_status: status,
        notes: definition.notes.iter().map(|note| note.to_string()).collect(),
    })
}

fn artifact(
    project_root: &Path,
    relative_path: &str,
    kind: &str,
) -> Result<FixtureArtifact, DynError> {
    Ok(FixtureArtifact {
        path: relative_path.to_string(),
        kind: kind.to_string(),
        sha256: artifact_sha256(&project_root.join(relative_path))?,
    })
}

fn official_evidence_record(
    project_root: &Path,
    definition: &FixtureDefinition,
    evidence_path: &str,
) -> Result<EvidenceRecord, DynError> {
    let mut notes = vec![
        "Generated by record_official_fixture_evidence from committed fixture artifacts and sanitized command metadata.".to_string(),
        "No ManyKee read/write parity claim is made by this KeePassXC lane evidence.".to_string(),
    ];
    notes.extend(fixture_evidence_notes(project_root, definition)?);

    Ok(EvidenceRecord {
        schema_version: 1,
        evidence_id: definition.fixture_id.to_string(),
        fixture_id: definition.fixture_id.to_string(),
        lane: EvidenceLane::KeepassXc,
        tool_name: "keepassxc-cli".to_string(),
        tool_version: REQUIRED_KEEPASSXC_VERSION.to_string(),
        status: SupportStatus::Supported,
        snapshot_path: None,
        snapshot_sha256: None,
        evidence_path: Some(evidence_path.to_string()),
        claims: definition
            .feature_ids
            .iter()
            .map(|feature_id| evidence_claim(feature_id, evidence_path))
            .collect(),
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        notes,
    })
}

fn fixture_evidence_notes(
    project_root: &Path,
    definition: &FixtureDefinition,
) -> Result<Vec<String>, DynError> {
    match definition.fixture_id {
        "keepassxc-attachments" => attachment_evidence_notes(project_root),
        "keepassxc-history-recycle-deleted" => Ok(vec![
            "HistoryEntry is retained after a KeePassXC edit so XML export contains <History> evidence.".to_string(),
            "DeletedEntry is removed through concrete recycle path Recycle Bin/DeletedEntry before permanent deletion.".to_string(),
            "KeePassXC XML export contains <DeletedObject> after the second rm; this evidence records Recycle Bin and DeletedObject behavior.".to_string(),
        ]),
        _ => Ok(Vec::new()),
    }
}

fn attachment_evidence_notes(project_root: &Path) -> Result<Vec<String>, DynError> {
    let mut notes = vec![
        "Attachment proof uses KeePassXC attachment-import followed by attachment-export; XML export is not used because KeePassXC omits attachments.".to_string(),
    ];
    for source in attachment_sources() {
        let source_hash = artifact_sha256(&project_root.join(source.relative_path))?;
        notes.push(format!(
            "attachment-export {} source_sha256={} exported_sha256={} matched=true",
            source.attachment_name, source_hash, source_hash
        ));
    }
    Ok(notes)
}

fn manual_evidence_artifacts(project_root: &Path) -> Result<Vec<GeneratedArtifact>, DynError> {
    Ok(vec![
        GeneratedArtifact {
            relative_path: MANUAL_CIPHER_KDF_EVIDENCE.to_string(),
            contents: pretty_json(&manual_cipher_kdf_evidence_record(
                project_root,
                MANUAL_CIPHER_KDF_EVIDENCE,
            )?)?,
        },
        GeneratedArtifact {
            relative_path: UNKNOWN_XML_MANUAL_EVIDENCE.to_string(),
            contents: pretty_json(&manual_unknown_xml_evidence_record(
                project_root,
                UNKNOWN_XML_MANUAL_EVIDENCE,
            )?)?,
        },
    ])
}

fn optional_keepass_evidence_artifact() -> Result<GeneratedArtifact, DynError> {
    Ok(GeneratedArtifact {
        relative_path: KEEPASS_OPTIONAL_NOT_OBSERVED_EVIDENCE.to_string(),
        contents: pretty_json(&optional_keepass_evidence_record(
            KEEPASS_OPTIONAL_NOT_OBSERVED_EVIDENCE,
        )?)?,
    })
}

fn optional_keepass_evidence_record(evidence_path: &str) -> Result<EvidenceRecord, DynError> {
    Ok(EvidenceRecord {
        schema_version: 1,
        evidence_id: "keepass-optional-cipher-kdf-not-observed".to_string(),
        fixture_id: "official-fixture-corpus".to_string(),
        lane: EvidenceLane::KeepassOptional,
        tool_name: "KeePass/KPScript".to_string(),
        tool_version: "KeePass 2.61 optional".to_string(),
        status: SupportStatus::NotObserved,
        snapshot_path: None,
        snapshot_sha256: None,
        evidence_path: Some(evidence_path.to_string()),
        claims: optional_keepass_claims(evidence_path),
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        notes: vec![
            "KeePass 2.61/KPScript evidence is optional and remains not_observed until a local runtime setup is validated.".to_string(),
            "This lane is separate from KeePassXC evidence and is not required by scripts or corpus tests.".to_string(),
            "No required optional-tool automation is added by this evidence record.".to_string(),
        ],
    })
}

fn optional_keepass_claims(evidence_path: &str) -> Vec<FeatureClaim> {
    fixture_definitions()
        .into_iter()
        .flat_map(|definition| {
            optional_keepass_claims_for(
                definition.fixture_id,
                definition.feature_ids,
                evidence_path,
            )
        })
        .chain(
            manual_fixture_definitions()
                .into_iter()
                .flat_map(|definition| {
                    optional_keepass_claims_for(
                        definition.fixture_id,
                        definition.feature_ids,
                        evidence_path,
                    )
                }),
        )
        .collect()
}

fn optional_keepass_claims_for(
    fixture_id: &'static str,
    feature_ids: &'static [&'static str],
    evidence_path: &str,
) -> Vec<FeatureClaim> {
    feature_ids
        .iter()
        .map(|feature_id| FeatureClaim {
            feature_id: (*feature_id).to_string(),
            status: SupportStatus::NotObserved,
            fixture_id: Some(fixture_id.to_string()),
            lane: Some(EvidenceLane::KeepassOptional),
            evidence_path: Some(evidence_path.to_string()),
            notes: vec![
                "KeePass 2.61/KPScript optional evidence has not been observed for this fixture."
                    .to_string(),
            ],
        })
        .collect()
}

fn manual_cipher_kdf_evidence_record(
    project_root: &Path,
    evidence_path: &str,
) -> Result<EvidenceRecord, DynError> {
    let definitions = manual_fixture_definitions()
        .into_iter()
        .filter(|definition| definition.fixture_id != "keepassxc-unknownxml")
        .collect::<Vec<_>>();
    let status = combined_manual_status(project_root, &definitions);

    Ok(EvidenceRecord {
        schema_version: 1,
        evidence_id: "keepassxc-manual-pending-cipher-kdf".to_string(),
        fixture_id: "keepassxc-gui-argon2id-aes".to_string(),
        lane: EvidenceLane::KeepassXc,
        tool_name: "keepassxc-gui".to_string(),
        tool_version: REQUIRED_KEEPASSXC_VERSION.to_string(),
        status,
        snapshot_path: None,
        snapshot_sha256: None,
        evidence_path: Some(evidence_path.to_string()),
        claims: definitions
            .iter()
            .flat_map(|definition| manual_claims(project_root, definition, evidence_path))
            .collect(),
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        notes: vec![
            "KeePassXC CLI 2.7.12 does not provide reliable fixture generation for all GUI cipher/KDF variants.".to_string(),
            "These claims remain manual_pending until provenance-clear GUI-created KDBX artifacts are committed under the manual fixture directory.".to_string(),
        ],
    })
}

fn manual_unknown_xml_evidence_record(
    project_root: &Path,
    evidence_path: &str,
) -> Result<EvidenceRecord, DynError> {
    let definition = manual_fixture_definitions()
        .into_iter()
        .find(|definition| definition.fixture_id == "keepassxc-unknownxml")
        .expect("unknown XML manual fixture definition exists");
    let status = manual_status(project_root, &definition);

    Ok(EvidenceRecord {
        schema_version: 1,
        evidence_id: "keepassxc-unknownxml-manual-pending".to_string(),
        fixture_id: definition.fixture_id.to_string(),
        lane: EvidenceLane::KeepassXc,
        tool_name: definition.source_tool.to_string(),
        tool_version: definition.source_version.to_string(),
        status,
        snapshot_path: None,
        snapshot_sha256: None,
        evidence_path: Some(evidence_path.to_string()),
        claims: manual_claims(project_root, &definition, evidence_path),
        known_gaps: Vec::new(),
        non_goals: Vec::new(),
        notes: vec![
            "KeePassXC XML import skips unknown XML and does not prove unknown XML preservation.".to_string(),
            "Unknown XML remains manual_pending until a provenance-clear KeePassXC GUI/plugin-generated source is committed.".to_string(),
        ],
    })
}

fn manual_claims(
    project_root: &Path,
    definition: &ManualFixtureDefinition,
    evidence_path: &str,
) -> Vec<FeatureClaim> {
    let status = manual_status(project_root, definition);
    definition
        .feature_ids
        .iter()
        .map(|feature_id| FeatureClaim {
            feature_id: (*feature_id).to_string(),
            status,
            fixture_id: Some(definition.fixture_id.to_string()),
            lane: Some(EvidenceLane::KeepassXc),
            evidence_path: Some(evidence_path.to_string()),
            notes: vec![if status == SupportStatus::ManualPending {
                "Manual fixture capture pending; no KeePassXC support claim is made yet."
                    .to_string()
            } else {
                "Manual fixture artifact is committed and hash-recorded by the official recorder."
                    .to_string()
            }],
        })
        .collect()
}

fn manual_status(project_root: &Path, definition: &ManualFixtureDefinition) -> SupportStatus {
    if project_root.join(definition.source_path).is_file() {
        SupportStatus::Manual
    } else {
        SupportStatus::ManualPending
    }
}

fn combined_manual_status(
    project_root: &Path,
    definitions: &[ManualFixtureDefinition],
) -> SupportStatus {
    if definitions
        .iter()
        .all(|definition| manual_status(project_root, definition) == SupportStatus::Manual)
    {
        SupportStatus::Manual
    } else {
        SupportStatus::ManualPending
    }
}

fn keepass_optional_not_observed_claims(
    fixture_id: &'static str,
    feature_ids: &'static [&'static str],
    note: &'static str,
) -> impl Iterator<Item = FeatureClaim> + 'static {
    feature_ids.iter().map(move |feature_id| FeatureClaim {
        feature_id: (*feature_id).to_string(),
        status: SupportStatus::NotObserved,
        fixture_id: Some(fixture_id.to_string()),
        lane: Some(EvidenceLane::KeepassOptional),
        evidence_path: None,
        notes: vec![note.to_string()],
    })
}

fn delegated_manykee_claims() -> Vec<FeatureClaim> {
    fixture_definitions()
        .into_iter()
        .flat_map(|definition| {
            definition.feature_ids.iter().flat_map(move |feature_id| {
                [EvidenceLane::ManyKeeRead, EvidenceLane::ManyKeeWrite]
                    .into_iter()
                    .map(move |lane| FeatureClaim {
                        feature_id: (*feature_id).to_string(),
                        status: SupportStatus::NotObserved,
                        fixture_id: Some(definition.fixture_id.to_string()),
                        lane: Some(lane),
                        evidence_path: None,
                        notes: vec![
                            " record_bidirectional_parity_evidence owns ManyKee parity lane backing; generated artifacts land in Plans 40-05 through 40-07."
                                .to_string(),
                        ],
                    })
            })
        })
        .collect()
}

fn non_keepassxc_not_observed_claims(
    fixture_id: &'static str,
    feature_ids: &'static [&'static str],
    note: &'static str,
) -> impl Iterator<Item = FeatureClaim> + 'static {
    feature_ids.iter().flat_map(move |feature_id| {
        [
            EvidenceLane::KeepassOptional,
            EvidenceLane::ManyKeeRead,
            EvidenceLane::ManyKeeWrite,
        ]
        .into_iter()
        .map(move |lane| FeatureClaim {
            feature_id: (*feature_id).to_string(),
            status: SupportStatus::NotObserved,
            fixture_id: Some(fixture_id.to_string()),
            lane: Some(lane),
            evidence_path: None,
            notes: vec![note.to_string()],
        })
    })
}

fn official_features() -> Vec<FeatureRow> {
    vec![
        feature(
            "credential_password_only",
            "Password-only credential",
            "KeePassXC-created database unlocked with a synthetic password provided through stdin.",
        ),
        feature(
            "credential_key_file_only",
            "Key-file-only credential",
            "KeePassXC-created database unlocked with --no-password and a committed synthetic key file.",
        ),
        feature(
            "credential_password_key_file",
            "Password plus key file credential",
            "KeePassXC-created database unlocked with both stdin password and --key-file.",
        ),
        feature(
            "cipher_aes256",
            "AES-256 cipher",
            "KeePassXC default AES-256 database cipher for CLI-created KDBX 4 files.",
        ),
        feature(
            "kdf_aes",
            "AES-KDF",
            "KeePassXC default AES-KDF metadata for CLI-created credential fixtures.",
        ),
        feature(
            "kdf_argon2id",
            "Argon2id KDF",
            "KeePassXC GUI/manual KDBX4 fixture using Argon2id.",
        ),
        feature(
            "kdf_argon2d",
            "Argon2d KDF",
            "KeePassXC GUI/manual KDBX4 fixture using Argon2d.",
        ),
        feature(
            "cipher_chacha20",
            "ChaCha20 cipher",
            "KeePassXC GUI/manual KDBX4 fixture using ChaCha20.",
        ),
        feature(
            "cipher_twofish",
            "Twofish cipher",
            "KeePassXC GUI/manual KDBX4 fixture using Twofish.",
        ),
        feature(
            "totp",
            "TOTP seed",
            "KeePassXC XML-imported TOTP URI stored in entry CustomData.",
        ),
    ]
}

fn feature(feature_id: &str, name: &str, description: &str) -> FeatureRow {
    FeatureRow {
        feature_id: feature_id.to_string(),
        name: name.to_string(),
        description: description.to_string(),
        lanes: vec![
            EvidenceLane::KeepassXc,
            EvidenceLane::KeepassOptional,
            EvidenceLane::ManyKeeRead,
            EvidenceLane::ManyKeeWrite,
        ],
        notes: Vec::new(),
    }
}

fn evidence_claim(feature_id: &str, evidence_path: &str) -> FeatureClaim {
    FeatureClaim {
        feature_id: feature_id.to_string(),
        status: SupportStatus::Supported,
        fixture_id: None,
        lane: None,
        evidence_path: Some(evidence_path.to_string()),
        notes: Vec::new(),
    }
}

fn credential_ref(definition: &FixtureDefinition) -> &'static str {
    match definition.credential_kind {
        CredentialKind::PasswordOnly => {
            "synthetic password fixture: manykee-fixture-password"
        }
        CredentialKind::KeyFileOnly => {
            "synthetic key-file fixture: keepassxc-keyfile-basic.keyx; no password"
        }
        CredentialKind::PasswordAndKeyFile => {
            "synthetic password fixture: manykee-fixture-password plus keepassxc-password-keyfile.keyx"
        }
    }
}

fn evidence_path(fixture_id: &str) -> String {
    format!("fixtures/compat/evidence/{fixture_id}.json")
}

fn manual_fixture_definitions() -> Vec<ManualFixtureDefinition> {
    vec![
        ManualFixtureDefinition {
            fixture_id: "keepassxc-gui-argon2id-aes",
            source_path: "fixtures/compat/official/keepassxc/2.7.12/manual/keepassxc-gui-argon2id-aes.kdbx",
            source_tool: "keepassxc-gui",
            source_version: REQUIRED_KEEPASSXC_VERSION,
            feature_ids: &["cipher_aes256", "kdf_argon2id"],
            expected_assertions: &[
                "Manual capture will assert KeePassXC GUI saved a KDBX4 database with AES-256 cipher and Argon2id KDF.",
                "No supported KeePassXC claim is made until the provenance-clear KDBX artifact is committed.",
            ],
            notes: &[
                "manual_pending because KeePassXC CLI generation does not reliably select this GUI cipher/KDF variant.",
            ],
        },
        ManualFixtureDefinition {
            fixture_id: "keepassxc-gui-argon2d-chacha20",
            source_path: "fixtures/compat/official/keepassxc/2.7.12/manual/keepassxc-gui-argon2d-chacha20.kdbx",
            source_tool: "keepassxc-gui",
            source_version: REQUIRED_KEEPASSXC_VERSION,
            feature_ids: &["cipher_chacha20", "kdf_argon2d"],
            expected_assertions: &[
                "Manual capture will assert KeePassXC GUI saved a KDBX4 database with ChaCha20 cipher and Argon2d KDF.",
                "No supported KeePassXC claim is made until the provenance-clear KDBX artifact is committed.",
            ],
            notes: &[
                "manual_pending because KeePassXC CLI generation does not reliably select this GUI cipher/KDF variant.",
            ],
        },
        ManualFixtureDefinition {
            fixture_id: "keepassxc-gui-argon2id-twofish",
            source_path: "fixtures/compat/official/keepassxc/2.7.12/manual/keepassxc-gui-argon2id-twofish.kdbx",
            source_tool: "keepassxc-gui",
            source_version: REQUIRED_KEEPASSXC_VERSION,
            feature_ids: &["cipher_twofish", "kdf_argon2id"],
            expected_assertions: &[
                "Manual capture will assert KeePassXC GUI saved a KDBX4 database with Twofish cipher and Argon2id KDF.",
                "No supported KeePassXC claim is made until the provenance-clear KDBX artifact is committed.",
            ],
            notes: &[
                "manual_pending because KeePassXC CLI generation does not reliably select this GUI cipher/KDF variant.",
            ],
        },
        ManualFixtureDefinition {
            fixture_id: "keepassxc-unknownxml",
            source_path: "fixtures/compat/official/keepassxc/2.7.12/manual/keepassxc-unknownxml.kdbx",
            source_tool: "keepassxc-gui-or-plugin",
            source_version: REQUIRED_KEEPASSXC_VERSION,
            feature_ids: &["unknown_xml"],
            expected_assertions: &[
                "No KeePassXC unknown XML support claim is made until a provenance-clear GUI/plugin-generated source exists.",
                "KeePassXC XML import skips unknown XML and does not prove unknown XML preservation.",
            ],
            notes: &[
                "manual_pending because research found KeePassXC XML import skips unknown XML.",
                "Unknown XML requires a provenance-clear KeePassXC GUI/plugin-generated source before this fixture can move beyond manual_pending.",
                "KeePassXC XML import does not prove unknown XML preservation.",
            ],
        },
    ]
}

fn manual_steps(definition: &ManualFixtureDefinition) -> Vec<String> {
    if definition.fixture_id == "keepassxc-unknownxml" {
        return vec![
            "Obtain or create a provenance-clear KeePassXC GUI/plugin-generated KDBX source that contains unknown XML.".to_string(),
            "Verify the unknown XML was not introduced only through KeePassXC XML import; XML import skips unknown XML and is not proof.".to_string(),
            format!(
                "Save the resulting KDBX under {MANUAL_DIR}/{}.kdbx.",
                definition.fixture_id
            ),
            "Run `cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_official_fixture_evidence -- --write` to capture hash/evidence once the file exists.".to_string(),
        ];
    }

    vec![
        "Open KeePassXC GUI 2.7.12.".to_string(),
        format!(
            "Create a new database named with the fixture ID `{}`.",
            definition.fixture_id
        ),
        "Set the synthetic password credential named in `credential_ref`.".to_string(),
        format!(
            "Select the cipher/KDF variant named by the fixture ID: {}.",
            definition.feature_ids.join(" plus ")
        ),
        format!(
            "Save the resulting KDBX under {MANUAL_DIR}/{}.kdbx.",
            definition.fixture_id
        ),
        "Run `cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_official_fixture_evidence -- --write` to capture hash/evidence once the file exists.".to_string(),
    ]
}

fn manual_readme_contents() -> String {
    let mut output = String::from(
        "# KeePassXC 2.7.12 Manual Fixture Capture\n\n\
This directory records manual-pending KeePassXC fixture categories that are not safely generated by the CLI recorder.\n\
The synthetic password credential for these pending fixtures is `manykee-fixture-password`.\n\
Do not mark a fixture supported until a provenance-clear KDBX artifact is committed and the recorder captures its hash.\n\n",
    );

    for definition in manual_fixture_definitions() {
        output.push_str(&format!("## {}\n\n", definition.fixture_id));
        output.push_str("Status: `manual_pending`\n\n");
        output.push_str(&format!("Source path: `{}`\n\n", definition.source_path));
        output.push_str(&format!(
            "Feature IDs: `{}`\n\n",
            definition.feature_ids.join("`, `")
        ));
        output.push_str("Manual steps:\n\n");
        for (index, step) in manual_steps(&definition).iter().enumerate() {
            output.push_str(&format!("{}. {}\n", index + 1, step));
        }
        output.push('\n');
        output.push_str("Pending reason:\n\n");
        for note in definition.notes {
            output.push_str(&format!("- {note}\n"));
        }
        output.push('\n');
    }

    output.push_str(
        "Unknown XML note: KeePassXC XML import skips unknown XML and does not prove unknown XML preservation.\n",
    );
    output
}

fn fixture_definitions() -> Vec<FixtureDefinition> {
    vec![
        FixtureDefinition {
            fixture_id: "keepassxc-password-basic",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-basic.kdbx",
            key_file_path: None,
            extra_artifacts: &[],
            credential_kind: CredentialKind::PasswordOnly,
            generation_command: "keepassxc-cli import -q -p <xml-source> <database>",
            generation_stdin: &["<fixture-password>", "<fixture-password>"],
            feature_ids: &[
                "credential_password_only",
                "cipher_aes256",
                "kdf_aes",
                "metadata",
                "group_tree",
                "standard_fields",
            ],
            expected_assertions: &[
                "KeePassXC opens the database with the fixture password supplied over stdin.",
                "KeePassXC imported /Root/Fixtures/BasicEntry from a temporary XML source.",
                "Manifest artifact SHA-256 matches the committed KDBX file.",
            ],
            notes: &[
                "KeePassXC imports a temporary password-basic XML source and saves keepassxc-password-basic.kdbx.",
            ],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-keyfile-basic",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-keyfile-basic.kdbx",
            key_file_path: Some("fixtures/compat/official/keepassxc/2.7.12/keepassxc-keyfile-basic.keyx"),
            extra_artifacts: &[],
            credential_kind: CredentialKind::KeyFileOnly,
            generation_command: "keepassxc-cli import -q --set-key-file <key-file> <xml-source> <database>",
            generation_stdin: &["y"],
            feature_ids: &[
                "credential_key_file_only",
                "cipher_aes256",
                "kdf_aes",
                "metadata",
            ],
            expected_assertions: &[
                "KeePassXC opens the database with --no-password and --key-file.",
                "Manifest artifact SHA-256 values match the committed KDBX and keyx files.",
            ],
            notes: &[
                "The key file is synthetic and committed beside the generated database.",
            ],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-password-keyfile",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-keyfile.kdbx",
            key_file_path: Some("fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-keyfile.keyx"),
            extra_artifacts: &[],
            credential_kind: CredentialKind::PasswordAndKeyFile,
            generation_command: "keepassxc-cli import -q -p --set-key-file <key-file> <xml-source> <database>",
            generation_stdin: &["<fixture-password>", "<fixture-password>", "y"],
            feature_ids: &[
                "credential_password_key_file",
                "cipher_aes256",
                "kdf_aes",
                "metadata",
            ],
            expected_assertions: &[
                "KeePassXC opens the database with the fixture password over stdin and --key-file.",
                "Manifest artifact SHA-256 values match the committed KDBX and keyx files.",
            ],
            notes: &[
                "The committed database requires both synthetic credential factors.",
            ],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-richcontent",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-richcontent.kdbx",
            key_file_path: None,
            extra_artifacts: &[],
            credential_kind: CredentialKind::PasswordOnly,
            generation_command: "keepassxc-cli import -q -p <xml-source> <database>",
            generation_stdin: &["<fixture-password>", "<fixture-password>"],
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
            expected_assertions: &[
                "KeePassXC imports a temporary synthetic XML source and saves keepassxc-richcontent.kdbx.",
                "Nested group /Fixtures/Nested contains StandardEntry, CustomFieldsEntry, ProtectedEntry, TOTPEntry, and AutoTypeEntry.",
                "TOTPEntry contains CustomData otp URI otpauth://totp/ManyKee:fixture?secret=JBSWY3DPEHPK3PXP&issuer=ManyKee.",
                "AutoTypeEntry contains enabled Auto-Type metadata with a default sequence and window association.",
                "Meta, group, and entry CustomData keys are present in the imported official fixture.",
                "Unknown XML is not claimed because KeePassXC XML import is not a safe unknown XML provenance source.",
            ],
            notes: &[
                "The XML source is generated in a temporary file by the recorder and is not committed.",
                "Attachment, history, recycle, and deleted-object coverage are separate official fixtures.",
            ],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-attachments",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-attachments.kdbx",
            key_file_path: None,
            extra_artifacts: &[
                (ATTACHMENT_TEXT_PATH, "source-attachment"),
                (ATTACHMENT_BINARY_PATH, "source-attachment"),
            ],
            credential_kind: CredentialKind::PasswordOnly,
            generation_command: "keepassxc-cli import -q -p <xml-source> <database>; attachment-import/export -q <database> Attachments/AttachmentEntry <attachment> <path>",
            generation_stdin: &[
                "<fixture-password>",
                "<fixture-password>",
                "<fixture-password>",
                "<fixture-password>",
                "<fixture-password>",
                "<fixture-password>",
            ],
            feature_ids: &["attachments_by_hash", "standard_fields", "group_tree"],
            expected_assertions: &[
                "KeePassXC imports Attachments/AttachmentEntry from a temporary XML source.",
                "KeePassXC attachment-import adds sample.txt and sample.bin from committed source files.",
                "KeePassXC attachment-export produces sample.txt and sample.bin bytes whose SHA-256 values match the source artifacts.",
                "Attachment evidence records source_sha256, exported_sha256, and matched=true for each payload.",
            ],
            notes: &[
                "Attachment proof intentionally uses attachment-export rather than XML export because KeePassXC XML export omits attachments.",
                "Source attachment files are committed under fixtures/compat/sources/keepassxc/2.7.12/.",
            ],
        },
        FixtureDefinition {
            fixture_id: "keepassxc-history-recycle-deleted",
            database_path: "fixtures/compat/official/keepassxc/2.7.12/keepassxc-history-recycle-deleted.kdbx",
            key_file_path: None,
            extra_artifacts: &[],
            credential_kind: CredentialKind::PasswordOnly,
            generation_command: "keepassxc-cli add/edit/rm/ls/export -q <database> <entry>",
            generation_stdin: &[
                "<fixture-password>",
                "<fixture-password>",
                "<fixture-password>",
                "<entry-password>",
                "<fixture-password>",
                "<entry-password>",
                "<fixture-password>",
                "<entry-password>",
                "<fixture-password>",
                "<fixture-password>",
                "<fixture-password>",
                "<fixture-password>",
            ],
            feature_ids: &["history", "deleted_objects", "group_tree", "standard_fields"],
            expected_assertions: &[
                "HistoryEntry is edited once and retained so KeePassXC XML export contains <History>.",
                "DeletedEntry is removed to the Recycle Bin, discovered through ls -q -R -f, and then removed from Recycle Bin/DeletedEntry.",
                "KeePassXC XML export contains <DeletedObject> after permanent deletion.",
                "Evidence records the concrete recycle path Recycle Bin/DeletedEntry.",
            ],
            notes: &[
                "HistoryEntry remains in the committed database to keep history evidence observable after DeletedObject creation.",
                "Recycle Bin/DeletedEntry is the concrete recycle path found by KeePassXC ls before permanent deletion.",
                "DeletedObject evidence is produced by deleting a separate DeletedEntry so history and deleted-object evidence coexist in one final fixture.",
            ],
        },
    ]
}

fn run_checked(tool: &OfficialTool, args: &[&str], stdin_lines: &[&str]) -> Result<(), DynError> {
    let args = args
        .iter()
        .map(|arg| project_relative_arg(arg))
        .collect::<Vec<_>>();
    run_checked_os(tool, &args, stdin_lines, &secret_redactions())?;
    Ok(())
}

fn run_checked_os(
    tool: &OfficialTool,
    args: &[OsString],
    stdin_lines: &[&str],
    redactions: &[&str],
) -> Result<RedactedOutput, DynError> {
    let output = run_keepassxc_with_stdin_lines(tool, args, stdin_lines, redactions)?;
    if !output.status.success() {
        return Err(io::Error::other(format!(
            "keepassxc-cli failed with status {}\nstdout:\n{}\nstderr:\n{}",
            output.status, output.stdout, output.stderr
        ))
        .into());
    }
    Ok(output)
}

fn run_keepassxc_with_stdin_lines(
    tool: &OfficialTool,
    args: &[OsString],
    stdin_lines: &[&str],
    redactions: &[&str],
) -> Result<RedactedOutput, DynError> {
    assert_no_secret_args(args, redactions)?;

    let mut child = Command::new(&tool.path)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| {
            io::Error::new(
                error.kind(),
                format!(
                    "failed to run keepassxc-cli at {}: {}",
                    redact_text(&tool.path.display().to_string(), redactions),
                    error.kind()
                ),
            )
        })?;

    if let Some(mut stdin) = child.stdin.take() {
        for line in stdin_lines {
            stdin.write_all(line.as_bytes())?;
            stdin.write_all(b"\n")?;
        }
    }

    let output = child.wait_with_output()?;
    Ok(RedactedOutput {
        status: output.status,
        stdout: redact_text(&String::from_utf8_lossy(&output.stdout), redactions),
        stderr: redact_text(&String::from_utf8_lossy(&output.stderr), redactions),
    })
}

fn project_relative_arg(arg: &str) -> OsString {
    if arg.starts_with("fixtures/") {
        project_root().join(arg).into_os_string()
    } else {
        OsString::from(arg)
    }
}

fn discover_required_keepassxc() -> Result<OfficialTool, DynError> {
    let configured_path = env::var_os(ENV_KEEPASSXC_CLI)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("keepassxc-cli"));
    let attempted_path = resolve_tool_path(&configured_path);
    let output = Command::new(&attempted_path).arg("--version").output()?;
    let discovered_version = normalize_keepassxc_version(&output.stdout, &output.stderr)
        .unwrap_or_else(|| "unavailable".to_string());

    if output.status.success() && discovered_version == REQUIRED_KEEPASSXC_VERSION {
        return Ok(OfficialTool {
            path: attempted_path,
        });
    }

    Err(io::Error::other(format!(
        "keepassxc-cli at {} reported version {}; expected version {}",
        attempted_path.display(),
        discovered_version,
        REQUIRED_KEEPASSXC_VERSION
    ))
    .into())
}

fn resolve_tool_path(path: &Path) -> PathBuf {
    if path.components().count() > 1 || path.is_absolute() {
        return path.to_path_buf();
    }

    let Some(paths) = env::var_os("PATH") else {
        return path.to_path_buf();
    };

    for dir in env::split_paths(&paths) {
        let candidate = dir.join(path);
        if candidate.is_file() {
            return candidate;
        }
    }

    path.to_path_buf()
}

fn normalize_keepassxc_version(stdout: &[u8], stderr: &[u8]) -> Option<String> {
    let stdout = String::from_utf8_lossy(stdout);
    let stderr = String::from_utf8_lossy(stderr);
    let text = if stdout.trim().is_empty() {
        stderr.trim()
    } else {
        stdout.trim()
    };

    text.split_whitespace()
        .find(|token| token.chars().all(|ch| ch.is_ascii_digit() || ch == '.'))
        .map(str::to_string)
}

fn assert_no_secret_args(args: &[OsString], secrets: &[&str]) -> Result<(), DynError> {
    for arg in args {
        let rendered = arg.to_string_lossy();
        if secrets
            .iter()
            .copied()
            .filter(|secret| !secret.is_empty())
            .any(|secret| rendered.contains(secret))
        {
            return Err(io::Error::other(format!(
                "refusing to spawn official tool with fixture secret in argv: {}",
                redact_text(rendered.as_ref(), secrets)
            ))
            .into());
        }
    }
    Ok(())
}

fn redact_text(text: &str, secrets: &[&str]) -> String {
    let mut redacted = text.to_string();
    for secret in secrets.iter().copied().filter(|secret| !secret.is_empty()) {
        redacted = redacted.replace(secret, "[REDACTED]");
    }
    redacted
}

fn remove_if_exists(path: PathBuf) -> Result<(), DynError> {
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

fn pretty_json<T: Serialize>(value: &T) -> Result<String, DynError> {
    let mut json = serde_json::to_string_pretty(value)?;
    json.push('\n');
    Ok(json)
}

fn project_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../..")
}

#[cfg(test)]
mod tests {
    use super::{build_manifest_section, fixture_definitions, project_root, EvidenceLane};
    use std::collections::BTreeSet;

    #[test]
    fn supported_official_manifest_delegates_manykee_parity_lanes() {
        let section = build_manifest_section(&project_root()).expect("manifest section builds");
        let supported_ids = fixture_definitions()
            .iter()
            .map(|definition| definition.fixture_id)
            .collect::<BTreeSet<_>>();
        let stale_manykee_claims = section
            .not_observed
            .iter()
            .filter(|claim| {
                claim
                    .fixture_id
                    .as_deref()
                    .is_some_and(|fixture_id| supported_ids.contains(fixture_id))
                    && matches!(
                        claim.lane,
                        Some(EvidenceLane::ManyKeeRead | EvidenceLane::ManyKeeWrite)
                    )
            })
            .collect::<Vec<_>>();

        assert!(
            stale_manykee_claims.is_empty(),
            " owns ManyKee parity lanes for supported official fixtures: {stale_manykee_claims:#?}"
        );
    }
}
