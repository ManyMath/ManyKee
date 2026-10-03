/// utility to purge the history of the entries in the database
use std::{
    fs::{self, File},
    io::Write,
    path::Path,
};

use anyhow::Result;
use clap::Parser;

use keepass::{Database, DatabaseKey};

#[derive(Parser, Debug)]
#[command(version, about)]
struct Args {
    /// Provide a .kdbx database
    in_kdbx: String,

    /// Provide a keyfile
    #[arg(short = 'k', long)]
    keyfile: Option<String>,

    /// Do not use a password to decrypt the database
    #[arg(short = 'n', long)]
    no_password: bool,
}

pub fn main() -> Result<()> {
    let args = Args::parse();

    let mut source = File::open(&args.in_kdbx)?;
    let mut key = DatabaseKey::new();

    if let Some(f) = args.keyfile {
        key = key.with_keyfile(&mut File::open(f)?)?;
    }

    if !args.no_password {
        key = key.with_password_from_prompt("Password: ")?;
    }

    if key.is_empty() {
        return Err(anyhow::format_err!("No database key was provided."));
    }

    let mut db = Database::open(&mut source, key.clone())?;

    purge_history(&mut db.root)?;

    // Serialise fully before touching the file, then replace it atomically,
    // so an error or a crash part-way through never damages the database.
    let mut out = Vec::new();
    db.save(&mut out, key)?;
    replace_file(Path::new(&args.in_kdbx), &out)?;

    Ok(())
}

/// Writes `bytes` to a sibling temp file, syncs it, and renames it over
/// `path`, keeping the original file's permissions.
fn replace_file(path: &Path, bytes: &[u8]) -> Result<()> {
    let file_name = path
        .file_name()
        .ok_or_else(|| anyhow::format_err!("{} is not a file path", path.display()))?;
    let mut temp_name = std::ffi::OsString::from(".");
    temp_name.push(file_name);
    temp_name.push(format!(".{}.tmp", std::process::id()));
    let temp_path = path.with_file_name(temp_name);

    let result = (|| -> Result<()> {
        let mut temp = File::options().write(true).create_new(true).open(&temp_path)?;
        temp.set_permissions(fs::metadata(path)?.permissions())?;
        temp.write_all(bytes)?;
        temp.sync_all()?;
        fs::rename(&temp_path, path)?;
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&temp_path);
    }
    result
}

fn purge_history_for_entry(entry: &mut keepass::db::Entry) -> Result<()> {
    if let Some(history) = &entry.history {
        let history_size = history.get_entries().len();
        if history_size != 0 {
            println!("Removing {} history entries from {}", history_size, entry.uuid);
        }
    }
    entry.history = None;
    Ok(())
}

fn purge_history(group: &mut keepass::db::Group) -> Result<()> {
    for entry in &mut group.entries {
        purge_history_for_entry(entry)?;
    }

    for group in &mut group.groups {
        purge_history(group)?;
    }

    Ok(())
}
