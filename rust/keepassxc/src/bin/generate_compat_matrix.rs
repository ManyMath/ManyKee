use keepassxc::compat_evidence::render_matrix_from_paths;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process;

const MANIFEST_PATH: &str = "fixtures/compat/manifest.json";
const EVIDENCE_DIR: &str = "fixtures/compat/evidence";
const MATRIX_PATH: &str = "docs/compatibility-matrix.md";

type DynError = Box<dyn std::error::Error>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Write,
    Check,
}

fn main() {
    let mode = match parse_mode() {
        Ok(mode) => mode,
        Err(message) => {
            eprintln!("{message}");
            eprintln!("usage: generate_compat_matrix (--write|--check)");
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
    let root = project_root()?;
    let generated = render_matrix_from_paths(&root.join(MANIFEST_PATH), &root.join(EVIDENCE_DIR))?;
    let matrix_path = root.join(MATRIX_PATH);

    match mode {
        Mode::Write => write_matrix(&matrix_path, &generated)?,
        Mode::Check => check_matrix(&matrix_path, &generated)?,
    }

    Ok(())
}

fn write_matrix(path: &Path, contents: &str) -> Result<(), DynError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, contents)?;
    Ok(())
}

fn check_matrix(path: &Path, generated: &str) -> Result<(), DynError> {
    let committed = fs::read_to_string(path).map_err(|source| {
        io::Error::new(
            source.kind(),
            format!("failed to read {}: {source}", MATRIX_PATH),
        )
    })?;

    if committed != generated {
        return Err(io::Error::new(
            io::ErrorKind::Other,
            format!("{MATRIX_PATH} is stale; run scripts/generate_compat_matrix.sh --write"),
        )
        .into());
    }

    Ok(())
}

fn project_root() -> Result<PathBuf, io::Error> {
    let mut current = PathBuf::from(env!("CARGO_MANIFEST_DIR"));

    loop {
        if current.join("rust/Cargo.toml").exists() && current.join(MANIFEST_PATH).exists() {
            return Ok(current);
        }

        if !current.pop() {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                "failed to locate repo root from CARGO_MANIFEST_DIR",
            ));
        }
    }
}
