//! Database FFI functions.

use std::ffi::{c_char, c_int, CString};
use std::fs::File;
use std::path::Path;

use keepassxc::{open_bytes, save_atomic, save_bytes, Database, DatabaseKey};

use crate::error::{
    check_null, clear_last_error, cstr_to_str, set_error_from_kpxc, set_last_error, KPXC_ERR_IO,
    KPXC_ERR_NULL_PTR, KPXC_OK,
};

/// Opaque handle wrapping a keepassxc Database.
pub struct KpxcDatabase(pub(crate) Database);

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

#[no_mangle]
pub extern "C" fn kpxc_database_open_bytes(
    bytes: *const u8,
    len: usize,
    password: *const c_char,
) -> *mut KpxcDatabase {
    clear_last_error();
    check_null!(bytes, std::ptr::null_mut());
    let password_str = cstr_to_str!(password, std::ptr::null_mut());
    let data = unsafe { std::slice::from_raw_parts(bytes, len) };

    let key = DatabaseKey::new().with_password(password_str);
    match open_bytes(data, key) {
        Ok(db) => Box::into_raw(Box::new(KpxcDatabase(db))),
        Err(e) => {
            set_error_from_kpxc(&e);
            std::ptr::null_mut()
        }
    }
}

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

#[no_mangle]
pub extern "C" fn kpxc_database_open_bytes_with_keyfile(
    bytes: *const u8,
    len: usize,
    password: *const c_char,
    keyfile_bytes: *const u8,
    keyfile_len: usize,
) -> *mut KpxcDatabase {
    clear_last_error();
    check_null!(bytes, std::ptr::null_mut());
    check_null!(keyfile_bytes, std::ptr::null_mut());
    let password_str = cstr_to_str!(password, std::ptr::null_mut());
    let data = unsafe { std::slice::from_raw_parts(bytes, len) };
    let kf_data = unsafe { std::slice::from_raw_parts(keyfile_bytes, keyfile_len) };

    let mut kf_cursor = std::io::Cursor::new(kf_data);
    let key = match DatabaseKey::new()
        .with_password(password_str)
        .with_keyfile(&mut kf_cursor)
    {
        Ok(k) => k,
        Err(e) => {
            set_last_error(&format!("Failed to read key file: {}", e));
            return std::ptr::null_mut();
        }
    };

    match open_bytes(data, key) {
        Ok(db) => Box::into_raw(Box::new(KpxcDatabase(db))),
        Err(e) => {
            set_error_from_kpxc(&e);
            std::ptr::null_mut()
        }
    }
}

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

    match save_atomic(&db.0, Path::new(path_str), key) {
        Ok(()) => KPXC_OK,
        Err(e) => set_error_from_kpxc(&e),
    }
}

#[no_mangle]
pub extern "C" fn kpxc_database_save_bytes(
    db: *mut KpxcDatabase,
    password: *const c_char,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    clear_last_error();
    check_null!(db, KPXC_ERR_NULL_PTR);
    check_null!(out_ptr, KPXC_ERR_NULL_PTR);
    check_null!(out_len, KPXC_ERR_NULL_PTR);
    let password_str = cstr_to_str!(password, KPXC_ERR_NULL_PTR);

    let db = unsafe { &*db };
    let key = DatabaseKey::new().with_password(password_str);

    match save_bytes(&db.0, key) {
        Ok(bytes) => {
            let mut boxed_slice = bytes.into_boxed_slice();
            unsafe {
                *out_ptr = boxed_slice.as_mut_ptr();
                *out_len = boxed_slice.len();
            }
            std::mem::forget(boxed_slice);
            KPXC_OK
        }
        Err(e) => set_error_from_kpxc(&e),
    }
}

#[no_mangle]
pub extern "C" fn kpxc_database_save_with_keyfile(
    db: *mut KpxcDatabase,
    path: *const c_char,
    password: *const c_char,
    keyfile_path: *const c_char,
) -> c_int {
    clear_last_error();
    check_null!(db, KPXC_ERR_NULL_PTR);
    let path_str = cstr_to_str!(path, KPXC_ERR_NULL_PTR);
    let password_str = cstr_to_str!(password, KPXC_ERR_NULL_PTR);
    let keyfile_str = cstr_to_str!(keyfile_path, KPXC_ERR_NULL_PTR);

    let mut keyfile = match File::open(keyfile_str) {
        Ok(file) => file,
        Err(error) => {
            set_last_error(&format!("Failed to open key file: {}", error));
            return KPXC_ERR_IO;
        }
    };

    let key = match DatabaseKey::new()
        .with_password(password_str)
        .with_keyfile(&mut keyfile)
    {
        Ok(key) => key,
        Err(error) => {
            set_last_error(&format!("Failed to read key file: {}", error));
            return KPXC_ERR_IO;
        }
    };

    let db = unsafe { &*db };
    match save_atomic(&db.0, Path::new(path_str), key) {
        Ok(()) => KPXC_OK,
        Err(error) => set_error_from_kpxc(&error),
    }
}

#[no_mangle]
pub extern "C" fn kpxc_database_save_bytes_with_keyfile(
    db: *mut KpxcDatabase,
    password: *const c_char,
    keyfile_bytes: *const u8,
    keyfile_len: usize,
    out_ptr: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    clear_last_error();
    check_null!(db, KPXC_ERR_NULL_PTR);
    check_null!(keyfile_bytes, KPXC_ERR_NULL_PTR);
    check_null!(out_ptr, KPXC_ERR_NULL_PTR);
    check_null!(out_len, KPXC_ERR_NULL_PTR);
    let password_str = cstr_to_str!(password, KPXC_ERR_NULL_PTR);

    let kf_data = unsafe { std::slice::from_raw_parts(keyfile_bytes, keyfile_len) };
    let mut kf_cursor = std::io::Cursor::new(kf_data);

    let key = match DatabaseKey::new()
        .with_password(password_str)
        .with_keyfile(&mut kf_cursor)
    {
        Ok(key) => key,
        Err(error) => {
            set_last_error(&format!("Failed to read key file: {}", error));
            return KPXC_ERR_IO;
        }
    };

    let db = unsafe { &*db };
    match save_bytes(&db.0, key) {
        Ok(bytes) => {
            let mut boxed_slice = bytes.into_boxed_slice();
            unsafe {
                *out_ptr = boxed_slice.as_mut_ptr();
                *out_len = boxed_slice.len();
            }
            std::mem::forget(boxed_slice);
            KPXC_OK
        }
        Err(e) => set_error_from_kpxc(&e),
    }
}

#[no_mangle]
pub extern "C" fn kpxc_bytes_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        unsafe {
            let _ = Box::from_raw(std::slice::from_raw_parts_mut(ptr, len));
        }
    }
}

#[no_mangle]
pub extern "C" fn kpxc_database_free(db: *mut KpxcDatabase) {
    if !db.is_null() {
        unsafe {
            drop(Box::from_raw(db));
        }
    }
}

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

#[cfg(test)]
mod tests {
    use super::*;
    use keepassxc::DatabaseConfig;

    #[test]
    fn database_save_uses_atomic_helper() {
        let db = Box::new(KpxcDatabase(Database::new(DatabaseConfig::default())));
        let db_ptr = Box::into_raw(db);
        let path = std::env::temp_dir().join(format!("ffi-save-{}.kdbx", uuid::Uuid::new_v4()));

        let path_c = CString::new(path.to_string_lossy().as_ref()).unwrap();
        let password = CString::new("test").unwrap();
        let result = kpxc_database_save(db_ptr, path_c.as_ptr(), password.as_ptr());
        assert_eq!(result, KPXC_OK);
        assert!(path.exists());

        let reopened = Database::open(
            &mut File::open(&path).unwrap(),
            DatabaseKey::new().with_password("test"),
        )
        .unwrap();
        assert_eq!(reopened.root.name, "Root");
        let _ = std::fs::remove_file(&path);

        unsafe {
            drop(Box::from_raw(db_ptr));
        }
    }
}
