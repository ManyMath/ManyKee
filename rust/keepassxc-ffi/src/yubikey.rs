//! YubiKey FFI functions.

use std::ffi::{c_char, c_int, CString};
use std::fs::File;
use std::path::Path;

use serde::Serialize;

use crate::database::KpxcDatabase;
use crate::error::{
    check_live_db, check_null, clear_last_error, cstr_to_str, set_error_from_kpxc, set_last_error,
    KPXC_ERR_IO, KPXC_ERR_NULL_PTR, KPXC_ERR_PANIC, KPXC_OK,
};

#[no_mangle]
pub extern "C" fn kpxc_database_open_with_yubikey(
    path: *const c_char,
    password: *const c_char,
    slot: *const c_char,
    serial: u32,
) -> *mut KpxcDatabase {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
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
            Ok(db) => crate::database::into_raw_registered(KpxcDatabase(db)),
            Err(e) => {
                set_error_from_kpxc(&e);
                std::ptr::null_mut()
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_database_open_with_local_challenge(
    path: *const c_char,
    password: *const c_char,
    hex_secret: *const c_char,
) -> *mut KpxcDatabase {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();
        let path_str = cstr_to_str!(path, std::ptr::null_mut());
        let password_str = cstr_to_str!(password, std::ptr::null_mut());
        let hex_secret_str = cstr_to_str!(hex_secret, std::ptr::null_mut());

        let mut file = match File::open(path_str) {
            Ok(f) => f,
            Err(e) => {
                set_last_error(&format!("Failed to open database file: {}", e));
                return std::ptr::null_mut();
            }
        };

        match keepassxc::open_with_local_challenge(&mut file, password_str, hex_secret_str) {
            Ok(db) => crate::database::into_raw_registered(KpxcDatabase(db)),
            Err(e) => {
                set_error_from_kpxc(&e);
                std::ptr::null_mut()
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_database_open_with_keyfile_and_yubikey(
    path: *const c_char,
    password: *const c_char,
    keyfile_path: *const c_char,
    slot: *const c_char,
    serial: u32,
) -> *mut KpxcDatabase {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();
        let path_str = cstr_to_str!(path, std::ptr::null_mut());
        let password_str = cstr_to_str!(password, std::ptr::null_mut());
        let keyfile_str = cstr_to_str!(keyfile_path, std::ptr::null_mut());
        let slot_str = cstr_to_str!(slot, std::ptr::null_mut());

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

        let serial_opt = if serial == 0 { None } else { Some(serial) };

        match keepassxc::open_with_yubikey_and_keyfile(
            &mut file,
            password_str,
            &mut keyfile,
            serial_opt,
            slot_str,
        ) {
            Ok(db) => crate::database::into_raw_registered(KpxcDatabase(db)),
            Err(e) => {
                set_error_from_kpxc(&e);
                std::ptr::null_mut()
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_database_open_with_keyfile_and_local_challenge(
    path: *const c_char,
    password: *const c_char,
    keyfile_path: *const c_char,
    hex_secret: *const c_char,
) -> *mut KpxcDatabase {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();
        let path_str = cstr_to_str!(path, std::ptr::null_mut());
        let password_str = cstr_to_str!(password, std::ptr::null_mut());
        let keyfile_str = cstr_to_str!(keyfile_path, std::ptr::null_mut());
        let hex_secret_str = cstr_to_str!(hex_secret, std::ptr::null_mut());

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

        match keepassxc::open_with_local_challenge_and_keyfile(
            &mut file,
            password_str,
            &mut keyfile,
            hex_secret_str,
        ) {
            Ok(db) => crate::database::into_raw_registered(KpxcDatabase(db)),
            Err(e) => {
                set_error_from_kpxc(&e);
                std::ptr::null_mut()
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_database_save_with_yubikey(
    db: *mut KpxcDatabase,
    path: *const c_char,
    password: *const c_char,
    slot: *const c_char,
    serial: u32,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_live_db!(db, KPXC_ERR_NULL_PTR);
        let path_str = cstr_to_str!(path, KPXC_ERR_NULL_PTR);
        let password_str = cstr_to_str!(password, KPXC_ERR_NULL_PTR);
        let slot_str = cstr_to_str!(slot, KPXC_ERR_NULL_PTR);

        let serial_opt = if serial == 0 { None } else { Some(serial) };
        let yubikey = match keepassxc::ChallengeResponseKey::get_yubikey(serial_opt) {
            Ok(yubikey) => yubikey,
            Err(error) => {
                let error = keepassxc::KeePassXcError::from(error);
                return set_error_from_kpxc(&error);
            }
        };

        let key = keepassxc::DatabaseKey::new()
            .with_password(password_str)
            .with_challenge_response_key(keepassxc::ChallengeResponseKey::YubikeyChallenge(
                yubikey,
                slot_str.to_string(),
            ));

        let db = unsafe { &*db };
        match keepassxc::save_atomic(&db.0, Path::new(path_str), key) {
            Ok(()) => KPXC_OK,
            Err(error) => set_error_from_kpxc(&error),
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_database_save_with_keyfile_and_yubikey(
    db: *mut KpxcDatabase,
    path: *const c_char,
    password: *const c_char,
    keyfile_path: *const c_char,
    slot: *const c_char,
    serial: u32,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_live_db!(db, KPXC_ERR_NULL_PTR);
        let path_str = cstr_to_str!(path, KPXC_ERR_NULL_PTR);
        let password_str = cstr_to_str!(password, KPXC_ERR_NULL_PTR);
        let keyfile_str = cstr_to_str!(keyfile_path, KPXC_ERR_NULL_PTR);
        let slot_str = cstr_to_str!(slot, KPXC_ERR_NULL_PTR);

        let mut keyfile = match File::open(keyfile_str) {
            Ok(file) => file,
            Err(error) => {
                set_last_error(&format!("Failed to open key file: {}", error));
                return KPXC_ERR_IO;
            }
        };
        let serial_opt = if serial == 0 { None } else { Some(serial) };
        let yubikey = match keepassxc::ChallengeResponseKey::get_yubikey(serial_opt) {
            Ok(yubikey) => yubikey,
            Err(error) => {
                let error = keepassxc::KeePassXcError::from(error);
                return set_error_from_kpxc(&error);
            }
        };

        let key = match keepassxc::DatabaseKey::new()
            .with_password(password_str)
            .with_keyfile(&mut keyfile)
        {
            Ok(key) => key.with_challenge_response_key(
                keepassxc::ChallengeResponseKey::YubikeyChallenge(yubikey, slot_str.to_string()),
            ),
            Err(error) => {
                set_last_error(&format!("Failed to read key file: {}", error));
                return KPXC_ERR_IO;
            }
        };

        let db = unsafe { &*db };
        match keepassxc::save_atomic(&db.0, Path::new(path_str), key) {
            Ok(()) => KPXC_OK,
            Err(error) => set_error_from_kpxc(&error),
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_database_save_with_local_challenge(
    db: *mut KpxcDatabase,
    path: *const c_char,
    password: *const c_char,
    hex_secret: *const c_char,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_live_db!(db, KPXC_ERR_NULL_PTR);
        let path_str = cstr_to_str!(path, KPXC_ERR_NULL_PTR);
        let password_str = cstr_to_str!(password, KPXC_ERR_NULL_PTR);
        let hex_secret_str = cstr_to_str!(hex_secret, KPXC_ERR_NULL_PTR);

        let key = keepassxc::DatabaseKey::new()
            .with_password(password_str)
            .with_challenge_response_key(keepassxc::ChallengeResponseKey::LocalChallenge(
                hex_secret_str.to_string(),
            ));

        let db = unsafe { &*db };
        match keepassxc::save_atomic(&db.0, Path::new(path_str), key) {
            Ok(()) => KPXC_OK,
            Err(error) => set_error_from_kpxc(&error),
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_database_save_with_keyfile_and_local_challenge(
    db: *mut KpxcDatabase,
    path: *const c_char,
    password: *const c_char,
    keyfile_path: *const c_char,
    hex_secret: *const c_char,
) -> c_int {
    crate::error::catch_unwind(KPXC_ERR_PANIC, move || {
        clear_last_error();
        check_live_db!(db, KPXC_ERR_NULL_PTR);
        let path_str = cstr_to_str!(path, KPXC_ERR_NULL_PTR);
        let password_str = cstr_to_str!(password, KPXC_ERR_NULL_PTR);
        let keyfile_str = cstr_to_str!(keyfile_path, KPXC_ERR_NULL_PTR);
        let hex_secret_str = cstr_to_str!(hex_secret, KPXC_ERR_NULL_PTR);

        let mut keyfile = match File::open(keyfile_str) {
            Ok(file) => file,
            Err(error) => {
                set_last_error(&format!("Failed to open key file: {}", error));
                return KPXC_ERR_IO;
            }
        };

        let key = match keepassxc::DatabaseKey::new()
            .with_password(password_str)
            .with_keyfile(&mut keyfile)
        {
            Ok(key) => key.with_challenge_response_key(
                keepassxc::ChallengeResponseKey::LocalChallenge(hex_secret_str.to_string()),
            ),
            Err(error) => {
                set_last_error(&format!("Failed to read key file: {}", error));
                return KPXC_ERR_IO;
            }
        };

        let db = unsafe { &*db };
        match keepassxc::save_atomic(&db.0, Path::new(path_str), key) {
            Ok(()) => KPXC_OK,
            Err(error) => set_error_from_kpxc(&error),
        }
    })
}

#[no_mangle]
pub extern "C" fn kpxc_yubikey_list() -> *mut c_char {
    crate::error::catch_unwind(std::ptr::null_mut(), move || {
        clear_last_error();

        match keepassxc::list_yubikeys() {
            Ok(yubikeys) => {
                let json = match yubikeys_to_json(&yubikeys) {
                    Ok(json) => json,
                    Err(e) => {
                        set_last_error(&format!("Failed to serialize YubiKey list: {}", e));
                        return std::ptr::null_mut();
                    }
                };

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
    })
}

#[derive(Serialize)]
struct YubikeyInfo<'a> {
    serial_number: u32,
    name: Option<&'a str>,
}

/// Serialise the device list for `kpxc_yubikey_list`. The device name comes
/// from the hardware/driver, so it goes through serde_json rather than
/// hand-rolled escaping, which only handled `\` and `"` and produced
/// invalid JSON for any control character.
fn yubikeys_to_json(yubikeys: &[keepassxc::Yubikey]) -> serde_json::Result<String> {
    let infos: Vec<YubikeyInfo<'_>> = yubikeys
        .iter()
        .map(|yk| YubikeyInfo {
            serial_number: yk.serial_number,
            name: yk.name.as_deref(),
        })
        .collect();
    serde_json::to_string(&infos)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn yubikey_json_escapes_control_characters_and_quotes() {
        let yubikeys = vec![
            keepassxc::Yubikey {
                serial_number: 12345,
                name: Some("Yubi\"Key\n5 \\ NFC\u{1}".to_string()),
            },
            keepassxc::Yubikey {
                serial_number: 67890,
                name: None,
            },
        ];

        let json = yubikeys_to_json(&yubikeys).unwrap();
        let parsed: serde_json::Value =
            serde_json::from_str(&json).expect("output must be valid JSON");

        assert_eq!(
            parsed,
            serde_json::json!([
                {"serial_number": 12345, "name": "Yubi\"Key\n5 \\ NFC\u{1}"},
                {"serial_number": 67890, "name": null},
            ])
        );
    }

    #[test]
    fn yubikey_json_empty_list() {
        assert_eq!(yubikeys_to_json(&[]).unwrap(), "[]");
    }
}
