//! Database FFI functions.

use std::ffi::{c_char, c_int, CString};
use std::fs::File;
use std::path::Path;

use keepassxc::{new_database, save_atomic, Database, DatabaseConfig, DatabaseKey};

use crate::error::{
    check_live_db, check_null, clear_last_error, cstr_to_str, set_error_from_kpxc, set_last_error,
    KPXC_ERR_IO, KPXC_ERR_NULL_PTR, KPXC_ERR_PANIC, KPXC_OK,
};

/// Opaque handle wrapping a keepassxc Database.
pub struct KpxcDatabase(pub(crate) Database);

/// Box-allocates `db`, registers the resulting pointer as a live handle (see
/// `handle_registry`), and returns it. Every FFI entry point that creates a
/// new `KpxcDatabase` handle to hand back to the caller must go through this
/// instead of a bare `Box::into_raw`.
pub(crate) fn into_raw_registered(db: KpxcDatabase) -> *mut KpxcDatabase {
    let ptr = Box::into_raw(Box::new(db));
    crate::handle_registry::register_database_handle(ptr);
    ptr
}

/// # Safety
///
/// `path` and `password` must each be null or point to a NUL-terminated string
/// that stays valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn kpxc_database_open(
    path: *const c_char,
    password: *const c_char,
) -> *mut KpxcDatabase {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
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
            Ok(db) => into_raw_registered(KpxcDatabase(db)),
            Err(e) => {
                let kpxc_err = keepassxc::KeePassXcError::Open(e);
                set_error_from_kpxc(&kpxc_err);
                std::ptr::null_mut()
            }
        }
    })
}

/// Create a new, empty KDBX4 database in memory (not yet saved to disk).
/// Mirrors the sensible-defaults `DatabaseConfig` (`keepass-rs`'s own
/// `Default` impl: KDBX4, AES256 outer cipher, ChaCha20 inner cipher,
/// Argon2 KDF) that `kpxc_database_save`'s own test coverage already
/// exercises, with the recycle bin enabled as KeePassXC does, so a caller
/// can create, soft-delete in, then save a fresh database via the existing
/// `kpxc_database_save`/`_with_keyfile` functions rather than needing a
/// template file to open first.
#[no_mangle]
pub extern "C" fn kpxc_database_create() -> *mut KpxcDatabase {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();
        into_raw_registered(KpxcDatabase(new_database(DatabaseConfig::default())))
    })
}

/// # Safety
///
/// `path`, `password` and `keyfile_path` must each be null or point to a
/// NUL-terminated string that stays valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn kpxc_database_open_with_keyfile(
    path: *const c_char,
    password: *const c_char,
    keyfile_path: *const c_char,
) -> *mut KpxcDatabase {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
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
            Ok(db) => into_raw_registered(KpxcDatabase(db)),
            Err(e) => {
                let kpxc_err = keepassxc::KeePassXcError::Open(e);
                set_error_from_kpxc(&kpxc_err);
                std::ptr::null_mut()
            }
        }
    })
}

/// # Safety
///
/// `db` must be null or a handle returned by this library that has not been
/// passed to `kpxc_database_free`, and no other call may use it at the same
/// time. `path` and `password` must each be null or point to a NUL-terminated
/// string that stays valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn kpxc_database_save(
    db: *mut KpxcDatabase,
    path: *const c_char,
    password: *const c_char,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_live_db!(db, KPXC_ERR_NULL_PTR);
        let path_str = cstr_to_str!(path, KPXC_ERR_NULL_PTR);
        let password_str = cstr_to_str!(password, KPXC_ERR_NULL_PTR);

        let db = unsafe { &*db };
        let key = DatabaseKey::new().with_password(password_str);

        match save_atomic(&db.0, Path::new(path_str), key) {
            Ok(()) => KPXC_OK,
            Err(e) => set_error_from_kpxc(&e),
        }
    })
}

/// # Safety
///
/// `db` must be null or a handle returned by this library that has not been
/// passed to `kpxc_database_free`, and no other call may use it at the same
/// time. `path`, `password` and `keyfile_path` must each be null or point to a
/// NUL-terminated string that stays valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn kpxc_database_save_with_keyfile(
    db: *mut KpxcDatabase,
    path: *const c_char,
    password: *const c_char,
    keyfile_path: *const c_char,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_live_db!(db, KPXC_ERR_NULL_PTR);
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
    })
}

/// # Safety
///
/// `db` must be null or a handle returned by this library that has not already
/// been freed, and no other call may be using it. It must not be used after
/// this call.
#[no_mangle]
pub unsafe extern "C" fn kpxc_database_free(db: *mut KpxcDatabase) {
    crate::error::catch_unwind((), move || {
        clear_last_error();
        if db.is_null() {
            return;
        }
        // Reusing a freed (but non-null) handle here is a double free, not
        // just a redundant no-op, unlike the null case above, a caller
        // that hits this has a real bug. Refuse to touch the pointer again
        // rather than risk a second `Box::from_raw` on already-freed memory.
        if !crate::handle_registry::unregister_database_handle(db) {
            set_last_error("attempted to free an invalid or already-freed database handle");
            return;
        }
        unsafe {
            drop(Box::from_raw(db));
        }
    })
}

/// # Safety
///
/// `db` must be null or a handle returned by this library that has not been
/// passed to `kpxc_database_free`, and no other call may use it at the same
/// time.
#[no_mangle]
pub unsafe extern "C" fn kpxc_database_root_uuid(db: *mut KpxcDatabase) -> *mut c_char {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();
        check_live_db!(db, std::ptr::null_mut());
        let db = unsafe { &*db };
        let uuid_str = db.0.root.uuid.to_string();
        match CString::new(uuid_str) {
            Ok(cs) => cs.into_raw(),
            Err(_) => {
                set_last_error("Failed to create UUID string");
                std::ptr::null_mut()
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use keepassxc::{DatabaseConfig, GroupExt};

    #[test]
    fn kpxc_database_create_returns_a_saveable_empty_database() {
        let db_ptr = kpxc_database_create();
        assert!(!db_ptr.is_null());

        let path = std::env::temp_dir().join(format!("ffi-create-{}.kdbx", uuid::Uuid::new_v4()));
        let path_c = CString::new(path.to_string_lossy().as_ref()).unwrap();
        let password = CString::new("test").unwrap();
        let result = unsafe { kpxc_database_save(db_ptr, path_c.as_ptr(), password.as_ptr()) };
        assert_eq!(result, KPXC_OK);

        let reopened = Database::open(
            &mut File::open(&path).unwrap(),
            DatabaseKey::new().with_password("test"),
        )
        .unwrap();
        assert_eq!(reopened.root.name, "Root");
        assert!(reopened.root.groups.is_empty());
        assert!(reopened.root.entries.is_empty());
        let _ = std::fs::remove_file(&path);

        unsafe { kpxc_database_free(db_ptr) };
    }

    #[test]
    fn kpxc_database_create_supports_soft_delete() {
        let db_ptr = kpxc_database_create();
        assert!(!db_ptr.is_null());

        let root_uuid = unsafe { crate::database::kpxc_database_root_uuid(db_ptr) };
        let root_uuid = unsafe { CString::from_raw(root_uuid) };
        let entry_uuid = unsafe { crate::entry::kpxc_entry_create(db_ptr, root_uuid.as_ptr()) };
        assert!(!entry_uuid.is_null());
        let entry_uuid = unsafe { CString::from_raw(entry_uuid) };

        // permanent = 0 is a soft delete, which needs the recycle bin.
        let result = unsafe { crate::entry::kpxc_entry_delete(db_ptr, entry_uuid.as_ptr(), 0) };
        assert_eq!(result, KPXC_OK, "{}", unsafe {
            std::ffi::CStr::from_ptr(crate::error::get_last_error())
                .to_string_lossy()
                .into_owned()
        });

        let db = unsafe { &*db_ptr };
        let entry_uuid: uuid::Uuid = entry_uuid.to_str().unwrap().parse().unwrap();
        let bin_uuid = db.0.meta.recyclebin_uuid.expect("recycle bin created");
        let bin = db.0.root.find_group_by_uuid(bin_uuid).unwrap();
        assert!(bin.entries.iter().any(|e| e.uuid == entry_uuid));
        assert!(db.0.root.entries.is_empty());

        unsafe { kpxc_database_free(db_ptr) };
    }

    #[test]
    fn database_save_uses_atomic_helper() {
        let db_ptr = into_raw_registered(KpxcDatabase(Database::new(DatabaseConfig::default())));
        let path = std::env::temp_dir().join(format!("ffi-save-{}.kdbx", uuid::Uuid::new_v4()));

        let path_c = CString::new(path.to_string_lossy().as_ref()).unwrap();
        let password = CString::new("test").unwrap();
        let result = unsafe { kpxc_database_save(db_ptr, path_c.as_ptr(), password.as_ptr()) };
        assert_eq!(result, KPXC_OK);
        assert!(path.exists());

        let reopened = Database::open(
            &mut File::open(&path).unwrap(),
            DatabaseKey::new().with_password("test"),
        )
        .unwrap();
        assert_eq!(reopened.root.name, "Root");
        let _ = std::fs::remove_file(&path);

        unsafe { kpxc_database_free(db_ptr) };
    }

    #[test]
    fn kpxc_database_free_rejects_double_free() {
        let db_ptr = into_raw_registered(KpxcDatabase(Database::new(DatabaseConfig::default())));

        // First free is legitimate: drops the Box and unregisters the handle.
        unsafe { kpxc_database_free(db_ptr) };
        // Second free of the same (now-dangling) pointer must not touch the
        // freed memory again, it should be rejected as an invalid handle
        // instead of double-freeing.
        unsafe { kpxc_database_free(db_ptr) };

        let err = unsafe { std::ffi::CStr::from_ptr(crate::error::get_last_error()) }
            .to_str()
            .unwrap();
        assert!(err.contains("already-freed"), "message was: {}", err);
    }

    #[test]
    fn kpxc_database_save_rejects_freed_handle() {
        let db_ptr = into_raw_registered(KpxcDatabase(Database::new(DatabaseConfig::default())));
        unsafe { kpxc_database_free(db_ptr) };

        let path =
            std::env::temp_dir().join(format!("ffi-save-freed-{}.kdbx", uuid::Uuid::new_v4()));
        let path_c = CString::new(path.to_string_lossy().as_ref()).unwrap();
        let password = CString::new("test").unwrap();

        // The pointer is dangling at this point; a correct implementation
        // must reject it via the handle registry before ever dereferencing
        // it, not attempt to read through it.
        let result = unsafe { kpxc_database_save(db_ptr, path_c.as_ptr(), password.as_ptr()) };
        assert_eq!(result, KPXC_ERR_NULL_PTR);
        assert!(!path.exists());
    }
}
