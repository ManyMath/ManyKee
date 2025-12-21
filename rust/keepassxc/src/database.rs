//! Database save helpers.

use std::fs::{remove_file, rename, OpenOptions};
use std::io::{BufWriter, Write};
use std::path::Path;

use uuid::Uuid;

use crate::{Database, DatabaseKey, KeePassXcError};

/// Save a database atomically by writing to a temporary file and renaming it.
///
/// The temporary file is created in the same directory as `path` so the final
/// rename stays on the same filesystem.
///
/// On Windows this uses `ReplaceFileW` when the destination already exists so
/// replace-existing saves remain atomic and the original file is preserved on
/// failure.
pub fn save_atomic(db: &Database, path: &Path, key: DatabaseKey) -> Result<(), KeePassXcError> {
    let directory = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));

    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("database.kdbx");
    let temp_path = directory.join(format!(".{file_name}.{}.tmp", Uuid::new_v4()));

    let file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temp_path)?;
    let mut writer = BufWriter::new(file);

    let save_result = db.save(&mut writer, key);
    if let Err(error) = save_result {
        let _ = writer.flush();
        drop(writer);
        let _ = remove_file(&temp_path);
        return Err(KeePassXcError::Save(error));
    }

    writer.flush()?;
    writer.get_ref().sync_all()?;
    drop(writer);

    if let Err(error) = replace_destination(&temp_path, path) {
        let _ = remove_file(&temp_path);
        return Err(KeePassXcError::Io(error));
    }

    Ok(())
}

#[cfg(not(windows))]
fn replace_destination(temp_path: &Path, path: &Path) -> std::io::Result<()> {
    rename(temp_path, path)
}

#[cfg(windows)]
fn replace_destination(temp_path: &Path, path: &Path) -> std::io::Result<()> {
    use std::iter::once;
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Storage::FileSystem::ReplaceFileW;

    if !path.exists() {
        return rename(temp_path, path);
    }

    let path_wide: Vec<u16> = path.as_os_str().encode_wide().chain(once(0)).collect();
    let temp_wide: Vec<u16> = temp_path.as_os_str().encode_wide().chain(once(0)).collect();

    let result = unsafe {
        ReplaceFileW(
            path_wide.as_ptr(),
            temp_wide.as_ptr(),
            std::ptr::null(),
            0,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        )
    };
    if result == 0 {
        return Err(std::io::Error::last_os_error());
    }

    Ok(())
}
