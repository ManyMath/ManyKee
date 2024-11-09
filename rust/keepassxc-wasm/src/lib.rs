//! WASM bindings for the keepassxc crate.
//!
//! Exposes KeePass database operations via wasm_bindgen for use in Web Workers.
//! State is managed via integer handles stored in thread_local storage.

use wasm_bindgen::prelude::*;

/// Smoke-test export: returns the crate version to verify WASM module loads.
#[wasm_bindgen]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}
