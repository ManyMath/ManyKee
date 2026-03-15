use std::env;
use std::ffi::OsString;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};

pub const REQUIRED_KEEPASSXC_VERSION: &str = "2.7.12";
pub const ENV_KEEPASSXC_CLI: &str = "MANYKEE_KEEPASSXC_CLI";
pub const ENV_REQUIRE_OFFICIAL_TOOLS: &str = "MANYKEE_REQUIRE_OFFICIAL_TOOLS";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ToolMode {
    Optional,
    Required,
}

#[derive(Clone, Debug)]
pub struct OfficialTool {
    pub path: PathBuf,
    pub version: String,
}

#[derive(Debug)]
pub struct RedactedOutput {
    pub status: ExitStatus,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Debug)]
pub struct ToolError {
    message: String,
}

impl std::fmt::Display for ToolError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for ToolError {}

pub fn mode_from_env() -> ToolMode {
    let Some(value) = env::var_os(ENV_REQUIRE_OFFICIAL_TOOLS) else {
        return ToolMode::Optional;
    };

    match value.to_string_lossy().as_ref() {
        "1" => ToolMode::Required,
        value if value.eq_ignore_ascii_case("true") => ToolMode::Required,
        value if value.eq_ignore_ascii_case("yes") => ToolMode::Required,
        _ => ToolMode::Optional,
    }
}

pub fn discover_keepassxc(mode: ToolMode) -> Result<Option<OfficialTool>, ToolError> {
    let configured_path = env::var_os(ENV_KEEPASSXC_CLI)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("keepassxc-cli"));
    let attempted_path = resolve_tool_path(&configured_path);

    let output = match Command::new(&attempted_path).arg("--version").output() {
        Ok(output) => output,
        Err(error) => {
            return match mode {
                ToolMode::Optional => Ok(None),
                ToolMode::Required => Err(ToolError::new(format!(
                    "failed to run keepassxc-cli at {}; expected version {}; discovered version unavailable ({})",
                    attempted_path.display(),
                    REQUIRED_KEEPASSXC_VERSION,
                    error.kind(),
                ))),
            };
        }
    };

    let discovered_version = normalize_keepassxc_version(&output.stdout, &output.stderr)
        .unwrap_or_else(|| "unavailable".to_string());

    if output.status.success() && discovered_version == REQUIRED_KEEPASSXC_VERSION {
        return Ok(Some(OfficialTool {
            path: attempted_path,
            version: discovered_version,
        }));
    }

    match mode {
        ToolMode::Optional => Ok(None),
        ToolMode::Required => Err(ToolError::new(format!(
            "keepassxc-cli at {} reported version {}; expected version {}",
            attempted_path.display(),
            discovered_version,
            REQUIRED_KEEPASSXC_VERSION,
        ))),
    }
}

pub fn run_keepassxc_with_stdin_lines(
    tool: &OfficialTool,
    args: &[OsString],
    stdin_lines: &[&str],
    redactions: &[&str],
) -> Result<RedactedOutput, ToolError> {
    assert_no_secret_args(args, redactions)?;

    let mut child = Command::new(&tool.path)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| {
            ToolError::new(format!(
                "failed to run keepassxc-cli at {}: {}",
                redact_text(&tool.path.display().to_string(), redactions),
                error.kind(),
            ))
        })?;

    if let Some(mut stdin) = child.stdin.take() {
        for line in stdin_lines {
            stdin.write_all(line.as_bytes()).map_err(|error| {
                ToolError::new(format!(
                    "failed writing keepassxc-cli stdin: {}",
                    error.kind()
                ))
            })?;
            stdin.write_all(b"\n").map_err(|error| {
                ToolError::new(format!(
                    "failed writing keepassxc-cli stdin: {}",
                    error.kind()
                ))
            })?;
        }
    }

    let output = child.wait_with_output().map_err(|error| {
        ToolError::new(format!(
            "failed waiting for keepassxc-cli at {}: {}",
            redact_text(&tool.path.display().to_string(), redactions),
            error.kind(),
        ))
    })?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    Ok(RedactedOutput {
        status: output.status,
        stdout: redact_text(stdout.as_ref(), redactions),
        stderr: redact_text(stderr.as_ref(), redactions),
    })
}

pub fn redact_text(text: &str, secrets: &[&str]) -> String {
    let mut redacted = text.to_string();
    for secret in secrets.iter().copied().filter(|secret| !secret.is_empty()) {
        redacted = redacted.replace(secret, "[REDACTED]");
    }
    redacted
}

pub fn assert_no_secret_args(args: &[OsString], secrets: &[&str]) -> Result<(), ToolError> {
    for arg in args {
        let rendered = arg.to_string_lossy();
        if secrets
            .iter()
            .copied()
            .filter(|secret| !secret.is_empty())
            .any(|secret| rendered.contains(secret))
        {
            return Err(ToolError::new(format!(
                "refusing to spawn official tool with fixture secret in argv: {}",
                redact_text(rendered.as_ref(), secrets),
            )));
        }
    }

    Ok(())
}

impl ToolError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
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
