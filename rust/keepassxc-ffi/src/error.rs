//! FFI error handling: error codes, thread-local last error, and KeePassXcError mapping.

use std::cell::RefCell;
use std::ffi::{c_int, CString};
use std::os::raw::c_char;

use keepassxc::KeePassXcError;

// Error code constants (exported via cbindgen to bindings.h)
pub const KPXC_OK: c_int = 0;
pub const KPXC_ERR_IO: c_int = -1;
pub const KPXC_ERR_OPEN: c_int = -2;
pub const KPXC_ERR_SAVE: c_int = -3;
pub const KPXC_ERR_NOT_FOUND: c_int = -4;
pub const KPXC_ERR_MERGE: c_int = -5;
pub const KPXC_ERR_YUBIKEY: c_int = -6;
pub const KPXC_ERR_NULL_PTR: c_int = -7;
pub const KPXC_ERR_INVALID_UTF8: c_int = -8;
pub const KPXC_ERR_PARSE: c_int = -9;

thread_local! {
 static LAST_ERROR: RefCell<Option<CString>> = const { RefCell::new(None) };
}

pub(crate) fn set_last_error(msg: &str) {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = CString::new(msg).ok();
    });
}

pub(crate) fn clear_last_error() {
    LAST_ERROR.with(|cell| {
        *cell.borrow_mut() = None;
    });
}

pub(crate) fn set_error_from_kpxc(e: &KeePassXcError) -> c_int {
    let msg = e.to_string();
    set_last_error(&msg);
    match e {
        KeePassXcError::Open(_) => KPXC_ERR_OPEN,
        KeePassXcError::Save(_) => KPXC_ERR_SAVE,
        KeePassXcError::EntryNotFound(_) | KeePassXcError::GroupNotFound(_) => KPXC_ERR_NOT_FOUND,
        KeePassXcError::RecycleBinDisabled => KPXC_ERR_NOT_FOUND,
        KeePassXcError::Io(_) => KPXC_ERR_IO,
        KeePassXcError::Merge(_) => KPXC_ERR_MERGE,
        KeePassXcError::ChallengeResponse(_) => KPXC_ERR_YUBIKEY,
        KeePassXcError::Parse(_) => KPXC_ERR_PARSE,
    }
}

pub(crate) fn get_last_error() -> *const c_char {
    LAST_ERROR.with(|cell| {
        let borrow = cell.borrow();
        match borrow.as_ref() {
            Some(cstr) => cstr.as_ptr(),
            None => std::ptr::null(),
        }
    })
}

macro_rules! check_null {
    ($ptr:expr, $ret:expr) => {
        if $ptr.is_null() {
            $crate::error::set_last_error("null pointer argument");
            return $ret;
        }
    };
}

macro_rules! cstr_to_str {
    ($ptr:expr, $ret:expr) => {{
        check_null!($ptr, $ret);
        match unsafe { std::ffi::CStr::from_ptr($ptr) }.to_str() {
            Ok(s) => s,
            Err(_) => {
                $crate::error::set_last_error("invalid UTF-8 in string argument");
                return $ret;
            }
        }
    }};
}

pub(crate) use check_null;
pub(crate) use cstr_to_str;
