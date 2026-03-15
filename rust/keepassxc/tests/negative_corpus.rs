//! Variant-level negative corpus for the KDBX4 open path.
//!
//! Each test mutates a single byte (or truncates) a committed known-good fixture
//! in memory and asserts the specific error variant produced by
//! `keepassxc::open_bytes`. No tampered fixture is ever written to disk.
//!
//! Inner-header corruption coverage is held at the keepass-rs unit-test
//! level (see `format::kdbx4::parse::inner_header_negative`) since reaching
//! the inner header through the full open path requires decrypting the
//! payload, mutating inside it, and re-encrypting with a valid HMAC + SHA.
//! The unit tests exercise `parse_inner_header` directly with
//! hand-constructed buffers that target `Kdbx4InnerHeaderError::UnexpectedEof`
//! on both the entry-header and oversized-entry-length paths.

mod common;

use common::mutations::{find_inner_header_start, find_outer_header_entry, mutate_bytes};

use keepass::error::{
    BlockStreamError, DatabaseFormatError, DatabaseKeyError, DatabaseOpenError,
    DatabaseVersionParseError, Kdbx4OpenError, Kdbx4OuterHeaderError, KdfConfigError,
};
use keepassxc::{
    open_bytes, save_bytes, ChallengeResponseKey, Database, DatabaseConfig, DatabaseKey,
    KeePassXcError,
};

/// Known-good source fixture. Pinned at compile time so a missing fixture fails
/// the build rather than a test runtime: .
const FIXTURE: &[u8] =
    include_bytes!("../../../fixtures/compat/official/keepassxc/2.7.12/keepassxc-password-basic.kdbx");

// Password matches the fixture's credential: see
// tests/bidirectional_parity.rs::FIXTURE_PASSWORD. The slice plan snapshot used
// the placeholder "password"; reality is "manykee-fixture-password".
const FIXTURE_PASSWORD: &str = "manykee-fixture-password";

fn fixture_key() -> DatabaseKey {
    DatabaseKey::new().with_password(FIXTURE_PASSWORD)
}

// Outer header constants duplicated locally to keep the test module independent
// of keepass-rs internal visibility. See kdbx4/mod.rs for the canonical values.
const HEADER_MASTER_SEED: u8 = 4;
const HEADER_KDF_PARAMS: u8 = 11;

/// Locate the byte offset of the $UUID value within a KDF_PARAMS entry buffer.
/// `entry_buffer_start` is the absolute offset (in the whole file) of the first
/// byte of the KDF_PARAMS VariantDictionary buffer. Returns the absolute offset
/// of the first byte of the $UUID value bytes (16-byte UUID payload).
fn find_kdf_uuid_value_offset(bytes: &[u8], entry_buffer_start: usize) -> Option<usize> {
    // VariantDictionary header: 2-byte version at [entry_buffer_start..+2].
    let mut pos = entry_buffer_start + 2;
    loop {
        let value_type = *bytes.get(pos)?;
        pos += 1;
        if value_type == 0 {
            return None;
        }
        let key_len =
            u32::from_le_bytes(bytes.get(pos..pos + 4)?.try_into().ok()?) as usize;
        pos += 4;
        let key = bytes.get(pos..pos + key_len)?;
        pos += key_len;
        let value_len =
            u32::from_le_bytes(bytes.get(pos..pos + 4)?.try_into().ok()?) as usize;
        pos += 4;
        let value_start = pos;
        pos += value_len;
        if key == b"$UUID" {
            return Some(value_start);
        }
    }
}

// ---- outer-header negative tests ----

#[test]
fn test_outer_header_sha_mismatch() {
    // Flip a byte inside the master_seed value (opaque 32-byte random data). The
    // header still parses cleanly but its SHA-256 no longer matches the stored
    // header hash at [inner_header_start..+32].
    let master_seed_offset =
        find_outer_header_entry(FIXTURE, HEADER_MASTER_SEED).expect("master seed entry present");
    // Skip the 5-byte entry header to reach the seed bytes, then flip a
    // mid-buffer byte.
    let flip_at = master_seed_offset + 5 + 10;
    let mutated = mutate_bytes(FIXTURE, flip_at, &[FIXTURE[flip_at] ^ 0xFF]);

    let err = open_bytes(&mutated, fixture_key()).expect_err("mutation must fail to open");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Format(DatabaseFormatError::Kdbx4(
            Kdbx4OpenError::HeaderHashMismatch,
        ))) => {}
        other => panic!("expected HeaderHashMismatch, got {:?}", other),
    }
}

#[test]
fn test_outer_header_hmac_mismatch() {
    // Flip a byte inside the 32-byte header HMAC region
    // [inner_header_start + 32 .. inner_header_start + 64]. The stored SHA still
    // matches (header bytes unchanged), but the HMAC does not, which is exactly
    // how a wrong-credential or tampered-HMAC scenario surfaces.
    let ihs = find_inner_header_start(FIXTURE);
    let flip_at = ihs + 32 + 5;
    let mutated = mutate_bytes(FIXTURE, flip_at, &[FIXTURE[flip_at] ^ 0xFF]);

    let err = open_bytes(&mutated, fixture_key()).expect_err("mutation must fail to open");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Key(DatabaseKeyError::IncorrectKey)) => {}
        other => panic!("expected Key(IncorrectKey), got {:?}", other),
    }
}

#[test]
fn test_outer_header_truncated_before_header_end() {
    // Truncate to `inner_header_start - 5`: the HEADER_END entry (5 bytes:
    // type=0, len=0) is chopped off, so parse_outer_header reads past EOF while
    // looking for the next entry_type byte.
    let ihs = find_inner_header_start(FIXTURE);
    let truncated = &FIXTURE[..ihs - 5];

    let err = open_bytes(truncated, fixture_key()).expect_err("truncation must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Format(DatabaseFormatError::Kdbx4(
            Kdbx4OpenError::OuterHeader(Kdbx4OuterHeaderError::UnexpectedEof),
        ))) => {}
        other => panic!("expected OuterHeader(UnexpectedEof), got {:?}", other),
    }
}

#[test]
fn test_outer_header_version_header_truncated() {
    // DatabaseVersion::parse requires at least 12 bytes.
    let truncated = &FIXTURE[..8];

    let err = open_bytes(truncated, fixture_key()).expect_err("8-byte input must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::VersionParse(
            DatabaseVersionParseError::UnexpectedEof,
        )) => {}
        other => panic!("expected VersionParse(UnexpectedEof), got {:?}", other),
    }
}

#[test]
fn test_outer_header_missing_master_seed() {
    // Overwrite the MASTER_SEED entry_type byte with HEADER_END (0). The parser
    // terminates the loop at the doctored end marker without ever recording a
    // master seed, so get_or_err returns Incomplete("Master seed").
    //
    // KeePassXC writes outer-header entries in numeric order (2 outer_cipher,
    // 3 compression, 4 master_seed, 7 outer_iv, 11 kdf_params), so by the time
    // the parser reaches the overwritten master_seed marker, outer_cipher and
    // compression have already been set and master_seed is the first missing
    // required field.
    let master_seed_offset =
        find_outer_header_entry(FIXTURE, HEADER_MASTER_SEED).expect("master seed entry present");
    let mutated = mutate_bytes(FIXTURE, master_seed_offset, &[0u8]);

    let err = open_bytes(&mutated, fixture_key()).expect_err("missing seed must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Format(DatabaseFormatError::Kdbx4(
            Kdbx4OpenError::OuterHeader(Kdbx4OuterHeaderError::Incomplete("Master seed")),
        ))) => {}
        other => panic!("expected Incomplete(\"Master seed\"), got {:?}", other),
    }
}

#[test]
fn test_outer_header_invalid_entry_type() {
    // Overwrite the first outer-header entry_type byte (at offset 12, just past
    // the 12-byte version header) with 0xFE, which is not a known entry type.
    let mutated = mutate_bytes(FIXTURE, 12, &[0xFE]);

    let err = open_bytes(&mutated, fixture_key()).expect_err("unknown entry type must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Format(DatabaseFormatError::Kdbx4(
            Kdbx4OpenError::OuterHeader(Kdbx4OuterHeaderError::InvalidEntry(0xFE)),
        ))) => {}
        other => panic!("expected InvalidEntry(0xFE), got {:?}", other),
    }
}

#[test]
fn test_outer_header_kdf_invalid_uuid() {
    // Locate the HEADER_KDF_PARAMS entry, then locate the $UUID key inside its
    // VariantDictionary value buffer, then flip a byte inside the 16-byte UUID
    // payload. The VD still parses cleanly, but the resulting UUID matches
    // none of the known KDF UUIDs (Argon2id/Argon2/AES-KDBX4/AES-KDBX3), so
    // TryInto produces KdfConfigError::InvalidKDFUUID.
    let kdf_entry_offset =
        find_outer_header_entry(FIXTURE, HEADER_KDF_PARAMS).expect("KDF params entry present");
    let kdf_buffer_start = kdf_entry_offset + 5;
    let uuid_value_offset = find_kdf_uuid_value_offset(FIXTURE, kdf_buffer_start)
        .expect("$UUID key present inside KDF VariantDictionary");
    // Flip the first byte of the UUID payload.
    let mutated = mutate_bytes(FIXTURE, uuid_value_offset, &[FIXTURE[uuid_value_offset] ^ 0xFF]);

    let err = open_bytes(&mutated, fixture_key()).expect_err("bogus KDF UUID must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Format(DatabaseFormatError::Kdbx4(
            Kdbx4OpenError::OuterHeader(Kdbx4OuterHeaderError::KdfConfig(
                KdfConfigError::InvalidKDFUUID { .. },
            )),
        ))) => {}
        other => panic!("expected KdfConfig(InvalidKDFUUID), got {:?}", other),
    }
}

// ---- block-stream negative tests ----

#[test]
fn test_block_stream_block0_hmac_mismatch() {
    // Flip a byte inside block 0's 32-byte HMAC prefix at
    // [inner_header_start + 64 .. inner_header_start + 96]. The size and body
    // are unchanged, so the block-stream parser reaches the HMAC comparison and
    // returns BlockHashMismatch { block_index: 0 }.
    let ihs = find_inner_header_start(FIXTURE);
    let flip_at = ihs + 64 + 5;
    let mutated = mutate_bytes(FIXTURE, flip_at, &[FIXTURE[flip_at] ^ 0xFF]);

    let err = open_bytes(&mutated, fixture_key()).expect_err("bad block HMAC must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Format(DatabaseFormatError::Kdbx4(
            Kdbx4OpenError::BlockStream(BlockStreamError::BlockHashMismatch { block_index: 0 }),
        ))) => {}
        other => panic!("expected BlockStream(BlockHashMismatch {{ 0 }}), got {:?}", other),
    }
}

#[test]
fn test_block_stream_truncated_mid_body() {
    // Truncate the file at inner_header_start + 196. Block 0's declared size is
    // unchanged (still pointing at the full block body), so the parser tries to
    // read size bytes past EOF and fails with BlockStreamError::Eof.
    let ihs = find_inner_header_start(FIXTURE);
    let truncate_to = ihs + 96 + 100;
    assert!(
        truncate_to < FIXTURE.len(),
        "fixture too small for mid-body truncation test"
    );
    let truncated = &FIXTURE[..truncate_to];

    let err = open_bytes(truncated, fixture_key()).expect_err("mid-body truncation must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Format(DatabaseFormatError::Kdbx4(
            Kdbx4OpenError::BlockStream(BlockStreamError::Eof),
        ))) => {}
        other => panic!("expected BlockStream(Eof), got {:?}", other),
    }
}

#[test]
fn test_block_stream_block0_size_tampered() {
    // Rewrite block 0's declared size (u32 LE at
    // [inner_header_start + 96 .. inner_header_start + 100]) to u32::MAX. The
    // parser reads a size that vastly exceeds input length and fails with
    // BlockStreamError::Eof.
    let ihs = find_inner_header_start(FIXTURE);
    let size_offset = ihs + 96;
    let mutated = mutate_bytes(FIXTURE, size_offset, &u32::MAX.to_le_bytes());

    let err = open_bytes(&mutated, fixture_key()).expect_err("tampered block size must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Format(DatabaseFormatError::Kdbx4(
            Kdbx4OpenError::BlockStream(BlockStreamError::Eof),
        ))) => {}
        other => panic!("expected BlockStream(Eof), got {:?}", other),
    }
}

// ---- wrong-credential variant assertions ----
//
// These tests strengthen the coverage already present in
// integration_tests.rs::test_invalid_key_fails and
// yubikey_tests.rs::test_local_challenge_wrong_secret_fails, which only assert
// the top-level error shape (is_err or KeePassXcError::Open(_)). A regression
// that collapsed DatabaseKeyError::IncorrectKey into a generic I/O or format
// error would pass those tests but should be caught here.
//
// In-memory round-trip only: no tampered bytes are written to disk, and the
// keyfile/challenge material is inline and never committed as a fixture.

fn empty_db() -> Database {
    Database::new(DatabaseConfig::default())
}

#[test]
fn test_wrong_password_asserts_incorrect_key() {
    let bytes = save_bytes(
        &empty_db(),
        DatabaseKey::new().with_password("alpha"),
    )
    .expect("save with password alpha must succeed");

    let err = open_bytes(&bytes, DatabaseKey::new().with_password("beta"))
        .expect_err("opening with a different password must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Key(DatabaseKeyError::IncorrectKey)) => {}
        other => panic!("expected Key(IncorrectKey), got {:?}", other),
    }
}

#[test]
fn test_wrong_keyfile_asserts_incorrect_key() {
    // Two distinct 32-byte "legacy binary" keyfiles. parse_keyfile treats any
    // 32-byte buffer as the raw key element, so flipping bytes here changes
    // the derived composite key and the HMAC check fails with IncorrectKey.
    let keyfile_a: [u8; 32] = [
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
        0x00, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90, 0xA0, 0xB0, 0xC0, 0xD0, 0xE0,
        0xF0, 0x01,
    ];
    let keyfile_b: [u8; 32] = [
        0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        0x99, 0x0A, 0x1B, 0x2C, 0x3D, 0x4E, 0x5F, 0x60, 0x71, 0x82, 0x93, 0xA4, 0xB5, 0xC6, 0xD7,
        0xE8, 0xF9,
    ];
    assert_ne!(keyfile_a, keyfile_b, "keyfile fixtures must differ");

    let bytes = save_bytes(
        &empty_db(),
        DatabaseKey::new()
            .with_password("shared")
            .with_keyfile(&mut keyfile_a.as_slice())
            .expect("with_keyfile A must succeed"),
    )
    .expect("save with keyfile A must succeed");

    let wrong_key = DatabaseKey::new()
        .with_password("shared")
        .with_keyfile(&mut keyfile_b.as_slice())
        .expect("with_keyfile B must succeed");
    let err = open_bytes(&bytes, wrong_key)
        .expect_err("opening with a different keyfile must fail");
    match err {
        KeePassXcError::Open(DatabaseOpenError::Key(DatabaseKeyError::IncorrectKey)) => {}
        other => panic!("expected Key(IncorrectKey), got {:?}", other),
    }
}

#[test]
fn test_wrong_local_challenge_asserts_specific_variant() {
    // Two distinct 20-byte hex secrets (40 hex chars each) for LocalChallenge.
    // Both parse as valid secrets so neither branch short-circuits on a hex
    // decoding error; the divergence is purely in the HMAC-SHA1 response and
    // therefore in the derived composite key.
    let hex_a = "0123456789abcdef0123456789abcdef01234567";
    let hex_b = "abcdef0123456789abcdef0123456789abcdef01";

    let bytes = save_bytes(
        &empty_db(),
        DatabaseKey::new()
            .with_password("shared")
            .with_challenge_response_key(ChallengeResponseKey::LocalChallenge(hex_a.to_string())),
    )
    .expect("save with LocalChallenge A must succeed");

    let wrong_key = DatabaseKey::new()
        .with_password("shared")
        .with_challenge_response_key(ChallengeResponseKey::LocalChallenge(hex_b.to_string()));
    let err = open_bytes(&bytes, wrong_key)
        .expect_err("opening with a different challenge secret must fail");

    // Observed on 2026-04-16 against keepass-rs parse_kdbx4: a wrong
    // LocalChallenge secret produces DatabaseKeyError::IncorrectKey because
    // perform_challenge still succeeds (HMAC-SHA1 over a different secret is
    // still a valid 20-byte response), but the derived composite key no
    // longer matches the stored header HMAC. If a future refactor short-
    // circuits earlier (e.g. exposes the challenge-response bytes as part of
    // the key-derivation contract and validates them up front), this test
    // would start producing DatabaseKeyError::ChallengeResponse(..) instead;
    // that is an acceptable variant. Update this comment when behavior shifts.
    match err {
        KeePassXcError::Open(DatabaseOpenError::Key(DatabaseKeyError::IncorrectKey)) => {}
        KeePassXcError::Open(DatabaseOpenError::Key(DatabaseKeyError::ChallengeResponse(_))) => {}
        other => panic!(
            "expected Key(IncorrectKey) or Key(ChallengeResponse(..)), got {:?}",
            other
        ),
    }
}

