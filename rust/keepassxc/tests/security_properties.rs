//! Security-property tests for the keepassxc open and save path.
//!
//! These tests assert invariants that hold across a class of inputs rather
//! than behavior on a single input: conceptually separate from the
//! variant-level assertions in `negative_corpus.rs`. They formalize:
//!
//! - The open path never panics on malformed bytes (seeded deterministic
//! truncation schedule over a known-good fixture).
//! - `save_atomic` leaves no partial writes on success or failure.
//! - Error `Display` and `Debug` renderings on the wrong-credential open path
//! never embed plaintext password bytes, keyfile bytes (UTF-8 or hex), or
//! LocalChallenge hex-secret material.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;

use keepassxc::{
    open_bytes, save_atomic, save_bytes, ChallengeResponseKey, Database, DatabaseConfig,
    DatabaseKey,
};

// Known-good KDBX4 source fixture, pinned at compile time so a missing or
// moved fixture fails the build rather than at runtime, matching the
// convention in `negative_corpus.rs`.
const FIXTURE: &[u8] =
    include_bytes!("../../../fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-basic.kdbx");

const FIXTURE_PASSWORD: &str = "manykee-fixture-password";

fn empty_db() -> Database {
    Database::new(DatabaseConfig::default())
}

// -----------------------------------------------------------------------------
// Property 1: the open path is panic-free under deterministic truncations.
// -----------------------------------------------------------------------------

#[test]
fn test_panic_free_on_deterministic_truncations() {
    // Deterministic, seeded schedule: any truncation that panics is
    // reproducible on rerun by a future engineer: .
    // 97 is coprime with typical fixture sizes (~10 KiB) so (i * 97 + 13)
    // spreads evenly across the truncation range without clustering.
    let fixture_len = FIXTURE.len();
    assert!(fixture_len > 0, "fixture must be non-empty");

    for i in 1u64..=100 {
        let len = ((i as usize) * 97 + 13) % fixture_len;

        // DatabaseKey is not UnwindSafe (Zeroize / ZeroizeOnDrop), so wrap the
        // whole closure in AssertUnwindSafe. Drop of a zeroize-on-drop key
        // cannot observe torn state since the key is local to this iteration.
        let key = DatabaseKey::new().with_password(FIXTURE_PASSWORD);
        let result = catch_unwind(AssertUnwindSafe(move || open_bytes(&FIXTURE[..len], key)));

        match result {
            Ok(Ok(_)) => panic!(
                "truncation_len={} (i={}) unexpectedly parsed as a valid database",
                len, i
            ),
            Ok(Err(_)) => {
                // Expected: the parser rejected the truncation with some error
                // variant. The point of this property is panic-free behavior,
                // not a specific variant per length.
            }
            Err(_) => panic!(
                "PANIC on truncation_len={} (i={}); reproduce locally with the same schedule",
                len, i
            ),
        }
    }
}

// -----------------------------------------------------------------------------
// Property 2: save_atomic produces no partial writes on success or failure.
// -----------------------------------------------------------------------------

fn count_tempfile_siblings(dir: &Path) -> usize {
    let mut count = 0;
    for entry in std::fs::read_dir(dir).expect("read_dir tempdir") {
        let entry = entry.expect("read_dir entry");
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with('.') && name.ends_with(".tmp") {
            count += 1;
        }
    }
    count
}

#[test]
fn test_save_atomic_no_partial_writes_on_success_or_failure() {
    // --- Happy path ---
    let tmp = tempfile::tempdir().expect("tempdir");
    let target = tmp.path().join("db.kdbx");
    save_atomic(
        &empty_db(),
        &target,
        DatabaseKey::new().with_password("shared"),
    )
    .expect("happy-path save_atomic must succeed");
    assert!(
        target.is_file(),
        "destination kdbx must exist as a file after successful save"
    );
    assert_eq!(
        count_tempfile_siblings(tmp.path()),
        0,
        "no .*.tmp siblings must linger after a successful save"
    );

    // --- Failure path ---
    //
    // Create a directory at the intended destination path. save_atomic
    // successfully creates its hidden `.target_dir.<uuid>.tmp` tempfile next
    // to the directory, but the final rename-over-an-existing-directory step
    // fails (Linux: ENOTDIR; macOS: similar; Windows: ReplaceFileW refuses).
    //
    // : assert only that save_atomic returns Err: the
    // specific OS-level error varies by platform. Do not match on the error
    // text.
    let fail_tmp = tempfile::tempdir().expect("tempdir for failure path");
    let target_dir = fail_tmp.path().join("target_dir");
    std::fs::create_dir(&target_dir).expect("pre-create target_dir");

    let result = save_atomic(
        &empty_db(),
        &target_dir,
        DatabaseKey::new().with_password("shared"),
    );
    assert!(
        result.is_err(),
        "save_atomic onto an existing-directory path must return Err"
    );
    assert!(
        target_dir.is_dir(),
        "pre-existing directory at the destination must be preserved on failure"
    );
    assert_eq!(
        count_tempfile_siblings(fail_tmp.path()),
        0,
        "no .*.tmp siblings must linger after a failed save"
    );
}

// -----------------------------------------------------------------------------
// Property 3: error formatting never leaks plaintext credential material.
// -----------------------------------------------------------------------------

/// Replace any hex-digit run of length >= 16 with `<REDACTED>` so the panic
/// message itself does not echo suspected credential bytes into the test log.
fn redact_hex_runs(input: &str) -> String {
    let mut out = String::new();
    let mut run = String::new();
    for c in input.chars() {
        if c.is_ascii_hexdigit() {
            run.push(c);
        } else {
            if run.len() >= 16 {
                out.push_str("<REDACTED>");
            } else {
                out.push_str(&run);
            }
            run.clear();
            out.push(c);
        }
    }
    if run.len() >= 16 {
        out.push_str("<REDACTED>");
    } else {
        out.push_str(&run);
    }
    out
}

fn assert_no_leak(scenario: &str, forbidden: &[(&str, String)], display: &str, debug: &str) {
    for (label, needle) in forbidden {
        if needle.is_empty() {
            continue;
        }
        for (rendering_label, rendering) in [("Display", display), ("Debug", debug)] {
            if rendering.contains(needle.as_str()) {
                let redacted = redact_hex_runs(rendering);
                let snippet: String = redacted.chars().take(120).collect();
                panic!(
                    "credential leak in scenario {}: kind={} appeared in {} rendering; first 120 chars (hex-redacted): {:?}",
                    scenario, label, rendering_label, snippet
                );
            }
        }
    }
}

// Distinctive sentinel strings (long, high-entropy) minimize the chance of a
// coincidental substring match in an unrelated error message.
const SHARED_PASSWORD: &str = "ManykeePolicy_SharedSentinel_do_not_leak";

#[test]
fn test_error_formatting_does_not_leak_credentials() {
    // --- Scenario 1: wrong password ---
    {
        let password_a = "ManykeePolicy_PW_alpha_sentinel_do_not_leak";
        let password_b = "ManykeePolicy_PW_beta_sentinel_do_not_leak";

        let bytes = save_bytes(&empty_db(), DatabaseKey::new().with_password(password_a))
            .expect("save with password A must succeed");
        let err = open_bytes(&bytes, DatabaseKey::new().with_password(password_b))
            .expect_err("opening with a different password must fail");
        let display = format!("{}", err);
        let debug = format!("{:?}", err);

        let forbidden = vec![
            ("password_a_utf8", password_a.to_string()),
            ("password_b_utf8", password_b.to_string()),
        ];
        assert_no_leak("wrong_password", &forbidden, &display, &debug);
    }

    // --- Scenario 2: wrong keyfile (with a shared password alongside) ---
    {
        // Exactly 32 bytes each: parse_keyfile treats a 32-byte buffer as a
        // legacy binary keyfile and uses the bytes verbatim. Printable ASCII
        // so we can additionally check the valid-UTF-8 substring path.
        let keyfile_a: [u8; 32] = *b"ManykeePolicy_KF_alpha_sentinel_";
        let keyfile_b: [u8; 32] = *b"ManykeePolicy_KF_beta__sentinel_";
        assert_ne!(keyfile_a, keyfile_b, "keyfile fixtures must differ");

        let bytes = save_bytes(
            &empty_db(),
            DatabaseKey::new()
                .with_password(SHARED_PASSWORD)
                .with_keyfile(&mut keyfile_a.as_slice())
                .expect("with_keyfile A must succeed"),
        )
        .expect("save with keyfile A must succeed");
        let wrong_key = DatabaseKey::new()
            .with_password(SHARED_PASSWORD)
            .with_keyfile(&mut keyfile_b.as_slice())
            .expect("with_keyfile B must succeed");
        let err = open_bytes(&bytes, wrong_key)
            .expect_err("opening with a different keyfile must fail");
        let display = format!("{}", err);
        let debug = format!("{:?}", err);

        let mut forbidden: Vec<(&str, String)> =
            vec![("shared_password_utf8", SHARED_PASSWORD.to_string())];
        if let Ok(s) = std::str::from_utf8(&keyfile_a) {
            forbidden.push(("keyfile_a_utf8", s.to_string()));
        }
        if let Ok(s) = std::str::from_utf8(&keyfile_b) {
            forbidden.push(("keyfile_b_utf8", s.to_string()));
        }
        forbidden.push(("keyfile_a_hex_lower", hex::encode(keyfile_a)));
        forbidden.push(("keyfile_a_hex_upper", hex::encode_upper(keyfile_a)));
        forbidden.push(("keyfile_b_hex_lower", hex::encode(keyfile_b)));
        forbidden.push(("keyfile_b_hex_upper", hex::encode_upper(keyfile_b)));
        assert_no_leak("wrong_keyfile", &forbidden, &display, &debug);
    }

    // --- Scenario 3: wrong LocalChallenge secret ---
    {
        // 20-byte hex secrets (40 hex chars). Both parse cleanly so
        // perform_challenge succeeds on both sides and the divergence is
        // purely in the HMAC-SHA1 response and derived composite key.
        let hex_a = "abcdef0123456789abcdef0123456789deadbeef";
        let hex_b = "fedcba9876543210fedcba9876543210beefdead";
        assert_ne!(hex_a, hex_b);

        let bytes = save_bytes(
            &empty_db(),
            DatabaseKey::new()
                .with_password(SHARED_PASSWORD)
                .with_challenge_response_key(ChallengeResponseKey::LocalChallenge(
                    hex_a.to_string(),
                )),
        )
        .expect("save with LocalChallenge A must succeed");
        let wrong_key = DatabaseKey::new()
            .with_password(SHARED_PASSWORD)
            .with_challenge_response_key(ChallengeResponseKey::LocalChallenge(hex_b.to_string()));
        let err = open_bytes(&bytes, wrong_key)
            .expect_err("opening with a different challenge secret must fail");
        let display = format!("{}", err);
        let debug = format!("{:?}", err);

        let decoded_a = hex::decode(hex_a).expect("hex_a decode");
        let decoded_b = hex::decode(hex_b).expect("hex_b decode");

        let forbidden = vec![
            ("shared_password_utf8", SHARED_PASSWORD.to_string()),
            ("cr_a_hex_lower", hex_a.to_ascii_lowercase()),
            ("cr_a_hex_upper", hex_a.to_ascii_uppercase()),
            ("cr_a_decoded_hex_lower", hex::encode(&decoded_a)),
            ("cr_a_decoded_hex_upper", hex::encode_upper(&decoded_a)),
            ("cr_b_hex_lower", hex_b.to_ascii_lowercase()),
            ("cr_b_hex_upper", hex_b.to_ascii_uppercase()),
            ("cr_b_decoded_hex_lower", hex::encode(&decoded_b)),
            ("cr_b_decoded_hex_upper", hex::encode_upper(&decoded_b)),
        ];
        assert_no_leak("wrong_local_challenge", &forbidden, &display, &debug);
    }
}
