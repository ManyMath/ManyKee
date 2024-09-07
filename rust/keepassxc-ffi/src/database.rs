//! Database open/save/free FFI functions.
//!
//! `KpxcDatabase` is an opaque handle wrapping `keepassxc::Database`.
//! Callers receive `*mut KpxcDatabase` from open functions and must
//! free it with `kpxc_database_free`.

use std::ffi::{c_char, c_int, CString};
use std::fs::File;
use std::io::BufWriter;

use keepassxc::{Database, DatabaseKey};

use crate::error::{
    check_null, clear_last_error, cstr_to_str, set_error_from_kpxc, set_last_error, KPXC_ERR_IO,
    KPXC_ERR_NULL_PTR, KPXC_OK,
};

/// Opaque handle wrapping a keepassxc Database.
pub struct KpxcDatabase(pub(crate) Database);

/// Open a KDBX database with a password.
///
/// Returns a heap-allocated `KpxcDatabase` handle, or null on error.
/// The caller must free the handle with `kpxc_database_free`.
#[no_mangle]
pub extern "C" fn kpxc_database_open(
    path: *const c_char,
    password: *const c_char,
) -> *mut KpxcDatabase {
    clear_last_error();
    let path_str = cstr_to_str!(path, std::ptr::null_mut());
    let password_str = cstr_to_str!(password, std::ptr::null_mut());

    let mut file = match File::open(path_str) {
        Ok(f) => f,
        Err(e) => {
            set_last_error(&format!("Failed to open file: {}", e));
            return std::ptr::null_mut();
        }
    };

    let key = DatabaseKey::new().with_password(password_str);
    match Database::open(&mut file, key) {
        Ok(db) => Box::into_raw(Box::new(KpxcDatabase(db))),
        Err(e) => {
            let kpxc_err = keepassxc::KeePassXcError::Open(e);
            set_error_from_kpxc(&kpxc_err);
            std::ptr::null_mut()
        }
    }
}

/// Open a KDBX database with a password and key file.
///
/// Returns a heap-allocated `KpxcDatabase` handle, or null on error.
/// The caller must free the handle with `kpxc_database_free`.
#[no_mangle]
pub extern "C" fn kpxc_database_open_with_keyfile(
    path: *const c_char,
    password: *const c_char,
    keyfile_path: *const c_char,
) -> *mut KpxcDatabase {
    clear_last_error();
    let path_str = cstr_to_str!(path, std::ptr::null_mut());
    let password_str = cstr_to_str!(password, std::ptr::null_mut());
    let keyfile_str = cstr_to_str!(keyfile_path, std::ptr::null_mut());

    let mut file = match File::open(path_str) {
        Ok(f) => f,
        Err(e) => {
            set_last_error(&format!("Failed to open database file: {}", e));
            return std::ptr::null_mut();
        }
    };

    let mut keyfile = match File::open(keyfile_str) {
        Ok(f) => f,
        Err(e) => {
            set_last_error(&format!("Failed to open key file: {}", e));
            return std::ptr::null_mut();
        }
    };

    let key = DatabaseKey::new().with_password(password_str);
    let key = match key.with_keyfile(&mut keyfile) {
        Ok(k) => k,
        Err(e) => {
            set_last_error(&format!("Failed to read key file: {}", e));
            return std::ptr::null_mut();
        }
    };

    match Database::open(&mut file, key) {
        Ok(db) => Box::into_raw(Box::new(KpxcDatabase(db))),
        Err(e) => {
            let kpxc_err = keepassxc::KeePassXcError::Open(e);
            set_error_from_kpxc(&kpxc_err);
            std::ptr::null_mut()
        }
    }
}

/// Save a database to a file path with a password.
///
/// Returns `KPXC_OK` on success, negative error code on failure.
#[no_mangle]
pub extern "C" fn kpxc_database_save(
    db: *mut KpxcDatabase,
    path: *const c_char,
    password: *const c_char,
) -> c_int {
    clear_last_error();
    check_null!(db, KPXC_ERR_NULL_PTR);
    let path_str = cstr_to_str!(path, KPXC_ERR_NULL_PTR);
    let password_str = cstr_to_str!(password, KPXC_ERR_NULL_PTR);

    let db = unsafe { &*db };
    let key = DatabaseKey::new().with_password(password_str);

    let file = match File::create(path_str) {
        Ok(f) => f,
        Err(e) => {
            set_last_error(&format!("Failed to create file: {}", e));
            return KPXC_ERR_IO;
        }
    };
    let mut writer = BufWriter::new(file);

    match db.0.save(&mut writer, key) {
        Ok(()) => KPXC_OK,
        Err(e) => {
            let kpxc_err = keepassxc::KeePassXcError::Save(e);
            set_error_from_kpxc(&kpxc_err)
        }
    }
}

/// Free a database handle.
///
/// Passing null is a no-op.
#[no_mangle]
pub extern "C" fn kpxc_database_free(db: *mut KpxcDatabase) {
    if !db.is_null() {
        unsafe {
            drop(Box::from_raw(db));
        }
    }
}

/// Return the UUID string of the root group.
///
/// Returns a heap-allocated string (caller frees with `kpxc_string_free`),
/// or null on error.
#[no_mangle]
pub extern "C" fn kpxc_database_root_uuid(db: *mut KpxcDatabase) -> *mut c_char {
    clear_last_error();
    check_null!(db, std::ptr::null_mut());
    let db = unsafe { &*db };
    let uuid_str = db.0.root.uuid.to_string();
    match CString::new(uuid_str) {
        Ok(cs) => cs.into_raw(),
        Err(_) => {
            set_last_error("Failed to create UUID string");
            std::ptr::null_mut()
        }
    }
}
