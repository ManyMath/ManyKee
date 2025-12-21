//! Database merge FFI function.

use std::ffi::{c_char, CString};

use serde::Serialize;

use crate::database::KpxcDatabase;
use crate::error::{check_null, clear_last_error, set_error_from_kpxc, set_last_error};

/// Serializable mirror of `keepassxc::MergeResult` for JSON output.
#[derive(Serialize)]
pub struct FfiMergeResult {
    pub entries_added: usize,
    pub entries_updated: usize,
    pub entries_deleted: usize,
    pub entries_relocated: usize,
    pub groups_added: usize,
    pub groups_updated: usize,
    pub groups_deleted: usize,
    pub groups_relocated: usize,
    pub total_changes: usize,
    pub conflicts_count: usize,
    pub warnings_count: usize,
    pub warnings: Vec<String>,
}

#[no_mangle]
pub extern "C" fn kpxc_database_merge(
    db: *mut KpxcDatabase,
    other: *mut KpxcDatabase,
) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    check_null!(other, std::ptr::null_mut());

    if std::ptr::eq(db, other) {
        set_last_error("Cannot merge a database with itself");
        return std::ptr::null_mut();
    }

    let db = unsafe { &mut *db };
    let other = unsafe { &*other };

    match keepassxc::merge(&mut db.0, &other.0) {
        Ok(result) => {
            let warnings: Vec<String> =
                result.warnings.iter().map(|w| format!("{:?}", w)).collect();

            let ffi_result = FfiMergeResult {
                entries_added: result.entries_added,
                entries_updated: result.entries_updated,
                entries_deleted: result.entries_deleted,
                entries_relocated: result.entries_relocated,
                groups_added: result.groups_added,
                groups_updated: result.groups_updated,
                groups_deleted: result.groups_deleted,
                groups_relocated: result.groups_relocated,
                total_changes: result.total_changes(),
                conflicts_count: result.conflicts.len(),
                warnings_count: result.warnings.len(),
                warnings,
            };

            match serde_json::to_string(&ffi_result) {
                Ok(json) => match CString::new(json) {
                    Ok(cs) => cs.into_raw(),
                    Err(_) => {
                        set_last_error("JSON contains null byte");
                        std::ptr::null_mut()
                    }
                },
                Err(e) => {
                    set_last_error(&format!("Failed to serialize merge result: {}", e));
                    std::ptr::null_mut()
                }
            }
        }
        Err(e) => {
            set_error_from_kpxc(&e);
            std::ptr::null_mut()
        }
    }
}
