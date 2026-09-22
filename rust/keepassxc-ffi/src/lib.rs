//! FFI bridge for keepassxc crate.

pub mod database;
pub mod entry;
pub mod error;
pub mod group;
mod handle_registry;
pub mod merge;
pub mod yubikey;

use std::ffi::{c_char, CString};

use zeroize::Zeroize;

#[no_mangle]
pub extern "C" fn kpxc_last_error() -> *const c_char {
    error::catch_unwind(std::ptr::null(), move || error::get_last_error())
}

/// Frees a string returned by this library. The bytes are overwritten with
/// zeros before the allocation is released, since these buffers can carry
/// plaintext secrets (e.g. a password from `kpxc_entry_get_field`).
#[no_mangle]
pub extern "C" fn kpxc_string_free(ptr: *mut c_char) {
    error::catch_unwind((), move || {
        if !ptr.is_null() {
            zeroize_and_free(unsafe { CString::from_raw(ptr) });
        }
    })
}

fn zeroize_and_free(string: CString) {
    // `into_bytes_with_nul` hands back the original allocation without
    // copying, so this wipes the very buffer the caller held.
    string.into_bytes_with_nul().zeroize();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn string_free_accepts_null_and_library_strings() {
        kpxc_string_free(std::ptr::null_mut());
        let secret = CString::new("hunter2").unwrap().into_raw();
        kpxc_string_free(secret);
    }

    #[test]
    fn into_bytes_with_nul_reuses_the_caller_buffer() {
        // zeroize_and_free relies on this: if the conversion copied, the
        // zeroing would hit the copy and leave the original plaintext.
        let raw = CString::new("hunter2").unwrap().into_raw();
        let bytes = unsafe { CString::from_raw(raw) }.into_bytes_with_nul();
        assert_eq!(bytes.as_ptr(), raw as *const u8);
        zeroize_and_free(CString::from_vec_with_nul(bytes).unwrap());
    }
}
