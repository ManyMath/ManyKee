//! Entry CRUD FFI functions — UUID-based access through database handle.
//!
//! All entry operations take `*mut KpxcDatabase` + UUID string to avoid
//! dangling pointer issues with borrowed interior data.

use std::ffi::{c_char, c_int, CString};

use keepassxc::{
    delete_entry, update_entry, Entry, EntryExt, EntryFieldExt, GroupExt,
};
use uuid::Uuid;

use crate::database::KpxcDatabase;
use crate::error::{
    check_null, clear_last_error, cstr_to_str, set_error_from_kpxc, set_last_error,
    KPXC_ERR_INVALID_UTF8, KPXC_ERR_NULL_PTR, KPXC_OK,
};

/// Parse a UUID string, setting last error on failure.
fn parse_uuid(s: &str) -> Result<Uuid, c_int> {
    Uuid::parse_str(s).map_err(|e| {
        set_last_error(&format!("Invalid UUID '{}': {}", s, e));
        KPXC_ERR_INVALID_UTF8
    })
}

/// Get a field value from an entry identified by UUID.
///
/// Returns a heap-allocated string (caller frees with `kpxc_string_free`),
/// or null if the entry/field is not found.
#[no_mangle]
pub extern "C" fn kpxc_entry_get_field(
    db: *mut KpxcDatabase,
    entry_uuid: *const c_char,
    field_name: *const c_char,
) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    let uuid_str = cstr_to_str!(entry_uuid, std::ptr::null_mut());
    let field_str = cstr_to_str!(field_name, std::ptr::null_mut());

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(_) => return std::ptr::null_mut(),
    };

    let db = unsafe { &*db };
    let entry = match db.0.root.find_entry_by_uuid(uuid) {
        Some(e) => e,
        None => {
            set_last_error(&format!("Entry not found: {}", uuid));
            return std::ptr::null_mut();
        }
    };

    match entry.get_field(field_str) {
        Some(value) => match CString::new(value) {
            Ok(cs) => cs.into_raw(),
            Err(_) => {
                set_last_error("Field value contains null byte");
                std::ptr::null_mut()
            }
        },
        None => {
            set_last_error(&format!("Field '{}' not found on entry {}", field_str, uuid));
            std::ptr::null_mut()
        }
    }
}

/// Set a field value on an entry identified by UUID (with history tracking).
///
/// `protected`: 1 for protected (e.g., Password), 0 for unprotected.
/// Returns `KPXC_OK` on success.
#[no_mangle]
pub extern "C" fn kpxc_entry_set_field(
    db: *mut KpxcDatabase,
    entry_uuid: *const c_char,
    field_name: *const c_char,
    value: *const c_char,
    protected: c_int,
) -> c_int {
    clear_last_error();
    check_null!(db, KPXC_ERR_NULL_PTR);
    let uuid_str = cstr_to_str!(entry_uuid, KPXC_ERR_NULL_PTR);
    let field_str = cstr_to_str!(field_name, KPXC_ERR_NULL_PTR);
    let value_str = cstr_to_str!(value, KPXC_ERR_NULL_PTR);

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(code) => return code,
    };

    let db = unsafe { &mut *db };
    let is_protected = protected != 0;

    // Capture field_str and value_str as owned strings for the closure
    let field_owned = field_str.to_string();
    let value_owned = value_str.to_string();

    let meta = db.0.meta.clone();
    match update_entry(&mut db.0.root, uuid, &meta, |e| {
        e.set_field(&field_owned, &value_owned, is_protected);
    }) {
        Ok(()) => KPXC_OK,
        Err(e) => set_error_from_kpxc(&e),
    }
}

/// Get the UUID of an entry at the given index within a group.
///
/// Returns a heap-allocated UUID string (caller frees with `kpxc_string_free`),
/// or null on error.
#[no_mangle]
pub extern "C" fn kpxc_entry_get_uuid(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
    index: usize,
) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    let uuid_str = cstr_to_str!(group_uuid, std::ptr::null_mut());

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(_) => return std::ptr::null_mut(),
    };

    let db = unsafe { &*db };
    let group = match db.0.root.find_group_by_uuid(uuid) {
        Some(g) => g,
        None => {
            set_last_error(&format!("Group not found: {}", uuid));
            return std::ptr::null_mut();
        }
    };

    match group.entries.get(index) {
        Some(entry) => match CString::new(entry.uuid.to_string()) {
            Ok(cs) => cs.into_raw(),
            Err(_) => {
                set_last_error("Failed to create UUID string");
                std::ptr::null_mut()
            }
        },
        None => {
            set_last_error(&format!("Entry index {} out of bounds", index));
            std::ptr::null_mut()
        }
    }
}

/// Create a new entry in the specified group.
///
/// Returns the new entry's UUID string (caller frees with `kpxc_string_free`),
/// or null on error.
#[no_mangle]
pub extern "C" fn kpxc_entry_create(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    let uuid_str = cstr_to_str!(group_uuid, std::ptr::null_mut());

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(_) => return std::ptr::null_mut(),
    };

    let db = unsafe { &mut *db };
    let group = match db.0.root.find_group_by_uuid_mut(uuid) {
        Some(g) => g,
        None => {
            set_last_error(&format!("Group not found: {}", uuid));
            return std::ptr::null_mut();
        }
    };

    let entry = Entry::new();
    let new_uuid = entry.uuid;
    group.add_entry(entry);

    match CString::new(new_uuid.to_string()) {
        Ok(cs) => cs.into_raw(),
        Err(_) => {
            set_last_error("Failed to create UUID string");
            std::ptr::null_mut()
        }
    }
}

/// Delete an entry by UUID.
///
/// If `permanent` is 0, soft-deletes (moves to recycle bin).
/// If `permanent` is 1, hard-deletes (removes entirely).
/// Returns `KPXC_OK` on success.
#[no_mangle]
pub extern "C" fn kpxc_entry_delete(
    db: *mut KpxcDatabase,
    entry_uuid: *const c_char,
    permanent: c_int,
) -> c_int {
    clear_last_error();
    check_null!(db, KPXC_ERR_NULL_PTR);
    let uuid_str = cstr_to_str!(entry_uuid, KPXC_ERR_NULL_PTR);

    let uuid = match parse_uuid(uuid_str) {
        Ok(u) => u,
        Err(code) => return code,
    };

    let db = unsafe { &mut *db };
    let soft = permanent == 0;

    match delete_entry(&mut db.0, uuid, soft) {
        Ok(()) => KPXC_OK,
        Err(e) => set_error_from_kpxc(&e),
    }
}
