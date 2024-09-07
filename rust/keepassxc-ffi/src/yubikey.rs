//! YubiKey FFI functions — open database with YubiKey and list devices.

use std::ffi::{c_char, CString};
use std::fs::File;

use crate::database::KpxcDatabase;
use crate::error::{check_null, clear_last_error, cstr_to_str, set_error_from_kpxc, set_last_error};

/// Open a KDBX database with password + YubiKey challenge-response.
///
/// `slot` is the YubiKey slot ("1" or "2").
/// `serial` is the YubiKey serial number; pass 0 to use the first detected YubiKey.
///
/// Returns a heap-allocated `KpxcDatabase` handle, or null on error.
#[no_mangle]
pub extern "C" fn kpxc_database_open_with_yubikey(
    path: *const c_char,
    password: *const c_char,
    slot: *const c_char,
    serial: u32,
) -> *mut KpxcDatabase {
    clear_last_error();
    let path_str = cstr_to_str!(path, std::ptr::null_mut());
    let password_str = cstr_to_str!(password, std::ptr::null_mut());
    let slot_str = cstr_to_str!(slot, std::ptr::null_mut());

    let mut file = match File::open(path_str) {
        Ok(f) => f,
        Err(e) => {
            set_last_error(&format!("Failed to open database file: {}", e));
            return std::ptr::null_mut();
        }
    };

    let serial_opt = if serial == 0 { None } else { Some(serial) };

    match keepassxc::open_with_yubikey(&mut file, password_str, serial_opt, slot_str) {
        Ok(db) => Box::into_raw(Box::new(KpxcDatabase(db))),
        Err(e) => {
            set_error_from_kpxc(&e);
            std::ptr::null_mut()
        }
    }
}

/// List all connected YubiKey devices capable of challenge-response.
///
/// Returns a JSON array string like `[{"serial_number":12345,"name":"YubiKey 5"}]`.
/// Caller frees with `kpxc_string_free`. Returns null on error.
#[no_mangle]
pub extern "C" fn kpxc_yubikey_list() -> *mut c_char {
    clear_last_error();

    match keepassxc::list_yubikeys() {
        Ok(yubikeys) => {
            // Build a simple JSON array manually (Yubikey doesn't derive Serialize)
            let entries: Vec<String> = yubikeys
                .iter()
                .map(|yk| {
                    let name = yk
                        .name
                        .as_deref()
                        .map(|n| format!("\"{}\"", n.replace('\\', "\\\\").replace('"', "\\\"")))
                        .unwrap_or_else(|| "null".to_string());
                    format!(
                        "{{\"serial_number\":{},\"name\":{}}}",
                        yk.serial_number, name
                    )
                })
                .collect();
            let json = format!("[{}]", entries.join(","));

            match CString::new(json) {
                Ok(cs) => cs.into_raw(),
                Err(_) => {
                    set_last_error("JSON contains null byte");
                    std::ptr::null_mut()
                }
            }
        }
        Err(e) => {
            set_error_from_kpxc(&e);
            std::ptr::null_mut()
        }
    }
}
