//! Group CRUD FFI functions.

use std::ffi::{c_char, c_int, CString};

use keepassxc::{delete_group, move_group, Group, GroupExt};

use crate::database::KpxcDatabase;
use crate::error::{
    check_null, clear_last_error, cstr_to_str, set_error_from_kpxc, set_last_error,
    KPXC_ERR_INVALID_UTF8, KPXC_ERR_NOT_FOUND, KPXC_ERR_NULL_PTR, KPXC_ERR_PANIC, KPXC_OK,
};

use uuid::Uuid;

/// Parse a UUID string, setting last error on failure.
fn parse_uuid(s: &str) -> Result<Uuid, c_int> {
    Uuid::parse_str(s).map_err(|e| {
        set_last_error(&format!("Invalid UUID '{}': {}", s, e));
        KPXC_ERR_INVALID_UTF8
    })
}

#[no_mangle]
pub extern "C" fn kpxc_group_get_name(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
) -> *mut c_char {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();
        check_null!(db, std::ptr::null_mut());
        let uuid_str = cstr_to_str!(group_uuid, std::ptr::null_mut());

        let uuid = match parse_uuid(uuid_str) {
            Ok(u) => u,
            Err(_) => return std::ptr::null_mut(),
        };

        let db = unsafe { &*db };
        match db.0.root.find_group_by_uuid(uuid) {
            Some(group) => match CString::new(group.name.clone()) {
                Ok(cs) => cs.into_raw(),
                Err(_) => {
                    set_last_error("Group name contains null byte");
                    std::ptr::null_mut()
                }
            },
            None => {
                set_last_error(&format!("Group not found: {}", uuid));
                std::ptr::null_mut()
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_group_set_name(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
    name: *const c_char,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_null!(db, KPXC_ERR_NULL_PTR);
        let uuid_str = cstr_to_str!(group_uuid, KPXC_ERR_NULL_PTR);
        let name_str = cstr_to_str!(name, KPXC_ERR_NULL_PTR);

        let uuid = match parse_uuid(uuid_str) {
            Ok(u) => u,
            Err(code) => return code,
        };

        let db = unsafe { &mut *db };
        match db.0.root.find_group_by_uuid_mut(uuid) {
            Some(group) => {
                group.name = name_str.to_string();
                KPXC_OK
            }
            None => {
                set_last_error(&format!("Group not found: {}", uuid));
                KPXC_ERR_NOT_FOUND
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_group_get_uuid(
    db: *mut KpxcDatabase,
    parent_uuid: *const c_char,
    index: usize,
) -> *mut c_char {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();
        check_null!(db, std::ptr::null_mut());
        let uuid_str = cstr_to_str!(parent_uuid, std::ptr::null_mut());

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

        match group.groups.get(index) {
            Some(child) => match CString::new(child.uuid.to_string()) {
                Ok(cs) => cs.into_raw(),
                Err(_) => {
                    set_last_error("Failed to create UUID string");
                    std::ptr::null_mut()
                }
            },
            None => {
                set_last_error(&format!("Group index {} out of bounds", index));
                std::ptr::null_mut()
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_group_entries_count(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_null!(db, KPXC_ERR_NULL_PTR);
        let uuid_str = cstr_to_str!(group_uuid, KPXC_ERR_NULL_PTR);

        let uuid = match parse_uuid(uuid_str) {
            Ok(u) => u,
            Err(code) => return code,
        };

        let db = unsafe { &*db };
        match db.0.root.find_group_by_uuid(uuid) {
            Some(group) => group.entries.len() as c_int,
            None => {
                set_last_error(&format!("Group not found: {}", uuid));
                KPXC_ERR_NOT_FOUND
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_group_groups_count(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_null!(db, KPXC_ERR_NULL_PTR);
        let uuid_str = cstr_to_str!(group_uuid, KPXC_ERR_NULL_PTR);

        let uuid = match parse_uuid(uuid_str) {
            Ok(u) => u,
            Err(code) => return code,
        };

        let db = unsafe { &*db };
        match db.0.root.find_group_by_uuid(uuid) {
            Some(group) => group.groups.len() as c_int,
            None => {
                set_last_error(&format!("Group not found: {}", uuid));
                KPXC_ERR_NOT_FOUND
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_group_create(
    db: *mut KpxcDatabase,
    parent_uuid: *const c_char,
    name: *const c_char,
) -> *mut c_char {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();
        check_null!(db, std::ptr::null_mut());
        let uuid_str = cstr_to_str!(parent_uuid, std::ptr::null_mut());
        let name_str = cstr_to_str!(name, std::ptr::null_mut());

        let uuid = match parse_uuid(uuid_str) {
            Ok(u) => u,
            Err(_) => return std::ptr::null_mut(),
        };

        let db = unsafe { &mut *db };
        let parent = match db.0.root.find_group_by_uuid_mut(uuid) {
            Some(g) => g,
            None => {
                set_last_error(&format!("Group not found: {}", uuid));
                return std::ptr::null_mut();
            }
        };

        let group = Group::new(name_str);
        let new_uuid = group.uuid;
        parent.add_group(group);

        match CString::new(new_uuid.to_string()) {
            Ok(cs) => cs.into_raw(),
            Err(_) => {
                set_last_error("Failed to create UUID string");
                std::ptr::null_mut()
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_group_delete(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
    permanent: c_int,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_null!(db, KPXC_ERR_NULL_PTR);
        let uuid_str = cstr_to_str!(group_uuid, KPXC_ERR_NULL_PTR);

        let uuid = match parse_uuid(uuid_str) {
            Ok(u) => u,
            Err(code) => return code,
        };

        let db = unsafe { &mut *db };
        let soft = permanent == 0;

        match delete_group(&mut db.0, uuid, soft) {
            Ok(()) => KPXC_OK,
            Err(e) => set_error_from_kpxc(&e),
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_group_root_uuid(db: *mut KpxcDatabase) -> *mut c_char {
    crate::database::kpxc_database_root_uuid(db)
}

#[no_mangle]
pub extern "C" fn kpxc_group_move(
    db: *mut KpxcDatabase,
    group_uuid: *const c_char,
    target_parent_uuid: *const c_char,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_null!(db, KPXC_ERR_NULL_PTR);
        let group_uuid = cstr_to_str!(group_uuid, KPXC_ERR_NULL_PTR);
        let target_parent_uuid = cstr_to_str!(target_parent_uuid, KPXC_ERR_NULL_PTR);

        let group_uuid = match parse_uuid(group_uuid) {
            Ok(uuid) => uuid,
            Err(code) => return code,
        };
        let target_parent_uuid = match parse_uuid(target_parent_uuid) {
            Ok(uuid) => uuid,
            Err(code) => return code,
        };

        let db = unsafe { &mut *db };
        match move_group(&mut db.0.root, group_uuid, target_parent_uuid) {
            Ok(()) => KPXC_OK,
            Err(error) => set_error_from_kpxc(&error),
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use keepassxc::{Database, DatabaseConfig};

    use crate::database::KpxcDatabase;

    #[test]
    fn group_move_updates_tree() {
        let mut db = Database::new(DatabaseConfig::default());
        let source = Group::new("Source");
        let source_uuid = source.uuid;
        let target = Group::new("Target");
        let target_uuid = target.uuid;
        db.root.groups.push(source);
        db.root.groups.push(target);

        let db_ptr = Box::into_raw(Box::new(KpxcDatabase(db)));
        let source_uuid = CString::new(source_uuid.to_string()).unwrap();
        let target_uuid = CString::new(target_uuid.to_string()).unwrap();

        let result = kpxc_group_move(db_ptr, source_uuid.as_ptr(), target_uuid.as_ptr());
        assert_eq!(result, KPXC_OK);

        let db = unsafe { &*db_ptr };
        assert_eq!(db.0.root.groups.len(), 1);
        assert_eq!(
            db.0.root.groups[0].uuid,
            target_uuid.to_str().unwrap().parse::<Uuid>().unwrap()
        );
        assert_eq!(db.0.root.groups[0].groups.len(), 1);

        unsafe {
            drop(Box::from_raw(db_ptr));
        }
    }
}
