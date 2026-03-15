mod common;

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use common::official_tools::{
    assert_no_secret_args, discover_keepassxc, mode_from_env, redact_text,
    run_keepassxc_with_stdin_lines, OfficialTool, ToolMode, ENV_KEEPASSXC_CLI,
    ENV_REQUIRE_OFFICIAL_TOOLS, REQUIRED_KEEPASSXC_VERSION,
};
use tempfile::TempDir;

fn env_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

struct EnvRestore {
    key: &'static str,
    previous: Option<OsString>,
}

impl EnvRestore {
    fn set(key: &'static str, value: impl Into<OsString>) -> Self {
        let previous = std::env::var_os(key);
        std::env::set_var(key, value.into());
        Self { key, previous }
    }

    fn remove(key: &'static str) -> Self {
        let previous = std::env::var_os(key);
        std::env::remove_var(key);
        Self { key, previous }
    }
}

impl Drop for EnvRestore {
    fn drop(&mut self) {
        if let Some(value) = self.previous.take() {
            std::env::set_var(self.key, value);
        } else {
            std::env::remove_var(self.key);
        }
    }
}

#[cfg(unix)]
fn fake_keepassxc_cli(dir: &TempDir, version_output: &str) -> PathBuf {
    use std::os::unix::fs::PermissionsExt;

    let path = dir.path().join("keepassxc-cli");
    std::fs::write(
        &path,
        format!("#!/usr/bin/env sh\nprintf '%s\\n' '{}'\n", version_output),
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&path).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(&path, permissions).unwrap();
    path
}

#[test]
#[cfg(unix)]
fn tool_discovery_optional_skips_missing_configured_binary() {
    let _guard = env_lock().lock().unwrap();
    let missing = TempDir::new().unwrap().path().join("missing-keepassxc-cli");
    let _cli = EnvRestore::set(ENV_KEEPASSXC_CLI, missing);

    let discovered = discover_keepassxc(ToolMode::Optional).unwrap();

    assert!(discovered.is_none());
}

#[test]
#[cfg(unix)]
fn tool_discovery_required_fails_missing_configured_binary() {
    let _guard = env_lock().lock().unwrap();
    let missing = TempDir::new().unwrap().path().join("missing-keepassxc-cli");
    let _cli = EnvRestore::set(ENV_KEEPASSXC_CLI, missing.clone());

    let err = discover_keepassxc(ToolMode::Required).unwrap_err();
    let rendered = err.to_string();

    assert!(rendered.contains(&missing.display().to_string()));
    assert!(rendered.contains(REQUIRED_KEEPASSXC_VERSION));
}

#[test]
#[cfg(unix)]
fn tool_discovery_optional_skips_wrong_version() {
    let _guard = env_lock().lock().unwrap();
    let tmp = TempDir::new().unwrap();
    let tool = fake_keepassxc_cli(&tmp, "2.7.11");
    let _cli = EnvRestore::set(ENV_KEEPASSXC_CLI, &tool);

    let discovered = discover_keepassxc(ToolMode::Optional).unwrap();

    assert!(discovered.is_none());
}

#[test]
#[cfg(unix)]
fn tool_discovery_required_fails_wrong_version() {
    let _guard = env_lock().lock().unwrap();
    let tmp = TempDir::new().unwrap();
    let tool = fake_keepassxc_cli(&tmp, "KeePassXC 2.7.11");
    let _cli = EnvRestore::set(ENV_KEEPASSXC_CLI, &tool);

    let err = discover_keepassxc(ToolMode::Required).unwrap_err();
    let rendered = err.to_string();

    assert!(rendered.contains(&tool.display().to_string()));
    assert!(rendered.contains(REQUIRED_KEEPASSXC_VERSION));
    assert!(rendered.contains("2.7.11"));
}

#[test]
#[cfg(unix)]
fn tool_discovery_required_accepts_exact_required_version() {
    let _guard = env_lock().lock().unwrap();
    let tmp = TempDir::new().unwrap();
    let tool = fake_keepassxc_cli(&tmp, "KeePassXC 2.7.12");
    let _cli = EnvRestore::set(ENV_KEEPASSXC_CLI, &tool);

    let discovered = discover_keepassxc(ToolMode::Required)
        .unwrap()
        .expect("required discovery should return a tool");

    assert_eq!(discovered.path, tool);
    assert_eq!(discovered.version, REQUIRED_KEEPASSXC_VERSION);
}

#[test]
fn tool_discovery_mode_from_env_requires_explicit_truthy_values() {
    let _guard = env_lock().lock().unwrap();

    for value in ["1", "true", "TRUE", "yes", "YeS"] {
        let _mode = EnvRestore::set(ENV_REQUIRE_OFFICIAL_TOOLS, value);
        assert_eq!(mode_from_env(), ToolMode::Required);
    }

    for value in ["", "0", "false", "required", "y"] {
        let _mode = EnvRestore::set(ENV_REQUIRE_OFFICIAL_TOOLS, value);
        assert_eq!(mode_from_env(), ToolMode::Optional);
    }

    let _mode = EnvRestore::remove(ENV_REQUIRE_OFFICIAL_TOOLS);
    assert_eq!(mode_from_env(), ToolMode::Optional);
}

#[test]
fn tool_discovery_real_keepassxc_reports_path_and_version() {
    let _guard = env_lock().lock().unwrap();
    let _cli = EnvRestore::remove(ENV_KEEPASSXC_CLI);

    let Some(discovered) = discover_keepassxc(ToolMode::Optional).unwrap() else {
        eprintln!("skipping real keepassxc-cli discovery: required version not available");
        return;
    };

    assert!(!discovered.path.as_os_str().is_empty());
    assert_eq!(discovered.version, REQUIRED_KEEPASSXC_VERSION);
    assert!(
        Path::new(&discovered.path).is_absolute()
            || discovered.path == PathBuf::from("keepassxc-cli")
    );
}

#[test]
fn secret_safety_rejects_password_in_argv() {
    let fixture_password = "manykee-test-password";
    let args = vec![
        OsString::from("show"),
        OsString::from(fixture_password),
        OsString::from("TestEntry"),
    ];

    let err = assert_no_secret_args(&args, &[fixture_password]).unwrap_err();
    let rendered = err.to_string();

    assert!(!rendered.contains(fixture_password));
    assert!(rendered.contains("[REDACTED]"));
}

#[test]
fn secret_safety_redacts_stdout_and_stderr() {
    let fixture_password = "manykee-test-password";
    let output = format!("stdout={fixture_password}\nstderr={fixture_password}");

    let redacted = redact_text(&output, &[fixture_password, ""]);

    assert!(!redacted.contains(fixture_password));
    assert_eq!(redacted.matches("[REDACTED]").count(), 2);
}

#[test]
#[cfg(unix)]
fn secret_safety_sends_password_through_stdin_and_redacts_output() {
    use std::os::unix::fs::PermissionsExt;

    let fixture_password = "manykee-test-password";
    let tmp = TempDir::new().unwrap();
    let path = tmp.path().join("keepassxc-cli");
    std::fs::write(
        &path,
        "#!/usr/bin/env sh\nprintf 'argv=%s\\n' \"$*\"\nIFS= read -r secret_line\nprintf 'stdin=%s\\n' \"$secret_line\"\nprintf 'stderr=%s\\n' \"$secret_line\" >&2\n",
    )
    .unwrap();
    let mut permissions = std::fs::metadata(&path).unwrap().permissions();
    permissions.set_mode(0o700);
    std::fs::set_permissions(&path, permissions).unwrap();

    let tool = OfficialTool {
        path,
        version: REQUIRED_KEEPASSXC_VERSION.to_string(),
    };
    let args = vec![
        OsString::from("show"),
        OsString::from("fixture.kdbx"),
        OsString::from("TestEntry"),
    ];

    let output =
        run_keepassxc_with_stdin_lines(&tool, &args, &[fixture_password], &[fixture_password])
            .unwrap();

    assert!(output.status.success());
    assert!(output.stdout.contains("argv=show fixture.kdbx TestEntry"));
    assert!(output.stdout.contains("stdin=[REDACTED]"));
    assert!(output.stderr.contains("stderr=[REDACTED]"));
    assert!(!output.stdout.contains(fixture_password));
    assert!(!output.stderr.contains(fixture_password));
}
