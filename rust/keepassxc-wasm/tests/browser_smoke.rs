use wasm_bindgen_test::*;

wasm_bindgen_test_configure!(run_in_browser);

#[wasm_bindgen_test]
fn smoke_runs_in_browser() {
    // Calls into the module so the smoke test proves it loaded and runs.
    assert_eq!(keepassxc_wasm::version(), env!("CARGO_PKG_VERSION"));
}
