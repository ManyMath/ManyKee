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
pub const KPXC_ERR_PANIC: c_int = -10;

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

/// Runs `f` behind `catch_unwind`, so a panic anywhere in the FFI call graph
/// (including in the `keepass-rs`/`keepassxc` core reached through it)
/// becomes a `KPXC_ERR_PANIC`-shaped error return instead of unwinding
/// across the `extern "C"` boundary, which is undefined behavior and in
/// practice aborts the host process.
pub(crate) fn catch_unwind<T>(default: T, f: impl FnOnce() -> T + std::panic::UnwindSafe) -> T {
    match std::panic::catch_unwind(f) {
        Ok(value) => value,
        Err(payload) => {
            let msg = if let Some(s) = payload.downcast_ref::<&str>() {
                s.to_string()
            } else if let Some(s) = payload.downcast_ref::<String>() {
                s.clone()
            } else {
                "unknown panic".to_string()
            };
            // `msg` is forwarded verbatim into `kpxc_last_error()`. Panic
            // messages bypass whatever logging/redaction review normal error
            // paths get, so no panic site anywhere in the call graph
            // (including keepass-rs/keepassxc) should ever interpolate
            // secret material (passwords, keys, decrypted field values) into
            // a panic!()/unwrap()/expect() message.
            set_last_error(&format!("internal panic: {}", msg));
            default
        }
    }
}

macro_rules! check_null {
    ($ptr:expr, $ret:expr) => {
        if $ptr.is_null() {
            $crate::error::set_last_error("null pointer argument");
            return $ret;
        }
    };
}

/// Like `check_null!`, but also rejects a non-null pointer that's been freed
/// (or was never a registered handle to begin with), see
/// `handle_registry`'s doc comment for what this does and doesn't catch.
macro_rules! check_live_db {
    ($ptr:expr, $ret:expr) => {
        check_null!($ptr, $ret);
        if !$crate::handle_registry::is_database_handle_live($ptr as *const $crate::database::KpxcDatabase) {
            $crate::error::set_last_error("invalid or already-freed database handle");
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

pub(crate) use check_live_db;
pub(crate) use check_null;
pub(crate) use cstr_to_str;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catch_unwind_converts_panic_into_default_and_sets_last_error() {
        clear_last_error();
        let result = catch_unwind(KPXC_ERR_PANIC, || -> c_int {
            panic!("boom: {}", "crafted input");
        });
        assert_eq!(result, KPXC_ERR_PANIC);

        let err = get_last_error();
        assert!(!err.is_null());
        let msg = unsafe { std::ffi::CStr::from_ptr(err) }.to_str().unwrap();
        assert!(msg.contains("boom: crafted input"), "message was: {}", msg);
    }

    #[test]
    fn catch_unwind_passes_through_ok_value() {
        let result = catch_unwind(KPXC_ERR_PANIC, || KPXC_OK);
        assert_eq!(result, KPXC_OK);
    }
}
