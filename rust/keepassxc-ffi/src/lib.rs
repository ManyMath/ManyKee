//! FFI bridge for keepassxc crate.

pub mod database;
pub mod entry;
pub mod error;
pub mod group;
pub mod merge;
pub mod yubikey;

use std::ffi::{c_char, CString};

#[no_mangle]
pub extern "C" fn kpxc_last_error() -> *const c_char {
 error::get_last_error()
}

#[no_mangle]
pub extern "C" fn kpxc_string_free(ptr: *mut c_char) {
 if !ptr.is_null() {
 unsafe {
 drop(CString::from_raw(ptr));
 }
 }
}
