//! Database merge FFI function.

use std::ffi::{c_char, CString};

use crate::database::KpxcDatabase;
use crate::error::{
    check_live_db, check_null, clear_last_error, set_error_from_kpxc, set_last_error,
};

use keepassxc::serialization::MergeInfo;

/// # Safety
///
/// `db` and `other` must each be null or a handle returned by this library that
/// has not been passed to `kpxc_database_free`, and no other call may use them
/// at the same time.
#[no_mangle]
pub unsafe extern "C" fn kpxc_database_merge(
    db: *mut KpxcDatabase,
    other: *mut KpxcDatabase,
) -> *mut c_char {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();
        check_live_db!(db, std::ptr::null_mut());
        check_live_db!(other, std::ptr::null_mut());

        if std::ptr::eq(db, other) {
            set_last_error("Cannot merge a database with itself");
            return std::ptr::null_mut();
        }

        let db = unsafe { &mut *db };
        let other = unsafe { &*other };

        match keepassxc::merge(&mut db.0, &other.0) {
            Ok(result) => {
                let info = MergeInfo::from(&result);
                match serde_json::to_string(&info) {
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
    })
}
