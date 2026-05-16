//! FFI bridge for keepassxc crate.

pub mod database;
pub mod entry;
pub mod error;
pub mod group;
mod handle_registry;
pub mod merge;
pub mod yubikey;

use std::ffi::{c_char, CString};

#[no_mangle]
pub extern "C" fn kpxc_last_error() -> *const c_char {
    error::catch_unwind(std::ptr::null(), move || error::get_last_error())
}

#[no_mangle]
pub extern "C" fn kpxc_string_free(ptr: *mut c_char) {
    error::catch_unwind((), move || {
        if !ptr.is_null() {
            unsafe {
                drop(CString::from_raw(ptr));
            }
        }
    })
}
