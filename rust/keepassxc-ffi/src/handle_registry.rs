//! Tracks which `KpxcDatabase` handle pointers are currently live, so a
//! caller (typically Dart via FFI) reusing an already-freed handle gets a
//! caught error return instead of triggering use-after-free/double-free
//! undefined behavior. Every FFI entry point already null-checks its
//! pointer arguments (see `error::check_null!`); this closes the separate
//! gap of a *freed but non-null* pointer being passed back in.
//!
//! This is deliberately a plain liveness set, not a generation-tagged one:
//! once an address is unregistered (freed) and later re-registered by a
//! brand new, legitimately-allocated `KpxcDatabase` that happens to reuse
//! the same address, treating it as live again is correct, it genuinely is
//! a live handle at that point. What this catches is a still-freed address
//! being handed back before any such reallocation happens.
//!
//! Note this can't validate that a pointer was ever a genuine `KpxcDatabase*`
//! to begin with, only that, if it was obtained from this crate, it hasn't
//! been freed since. That's the same trust boundary every other FFI
//! function here already assumes of its caller.

use std::collections::HashSet;
use std::sync::{LazyLock, Mutex};

use crate::database::KpxcDatabase;

static LIVE_DATABASE_HANDLES: LazyLock<Mutex<HashSet<usize>>> = LazyLock::new(|| Mutex::new(HashSet::new()));

/// Marks `ptr` as a live, allocated handle. Every FFI entry point that hands
/// a freshly-allocated `*mut KpxcDatabase` back to the caller must call this
/// before returning it.
pub(crate) fn register_database_handle(ptr: *mut KpxcDatabase) {
    LIVE_DATABASE_HANDLES.lock().unwrap().insert(ptr as usize);
}

/// Whether `ptr` currently refers to a registered, not-yet-freed handle.
pub(crate) fn is_database_handle_live(ptr: *const KpxcDatabase) -> bool {
    LIVE_DATABASE_HANDLES.lock().unwrap().contains(&(ptr as usize))
}

/// Unregisters `ptr`, returning whether it was actually live beforehand -
/// `false` means double-free or a handle that was never (successfully)
/// registered.
pub(crate) fn unregister_database_handle(ptr: *mut KpxcDatabase) -> bool {
    LIVE_DATABASE_HANDLES.lock().unwrap().remove(&(ptr as usize))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn register_then_live_then_unregister_then_dead() {
        let ptr = 0x1234usize as *mut KpxcDatabase;
        assert!(!is_database_handle_live(ptr));
        register_database_handle(ptr);
        assert!(is_database_handle_live(ptr));
        assert!(unregister_database_handle(ptr));
        assert!(!is_database_handle_live(ptr));
    }

    #[test]
    fn unregister_of_never_registered_handle_returns_false() {
        let ptr = 0x5678usize as *mut KpxcDatabase;
        assert!(!unregister_database_handle(ptr));
    }
}
