//! In-memory byte-mutation helpers for KDBX4 negative corpus tests.
//!
//! These helpers locate structural offsets inside a known-good KDBX4 byte stream
//! and apply targeted patches without writing any tampered fixture to disk.

const VERSION_HEADER_SIZE: usize = 12;
const HEADER_END: u8 = 0;

/// Locate the byte offset immediately after the outer header's HEADER_END entry.
///
/// This is the start of the 32-byte header SHA-256, which is immediately
/// followed by the 32-byte header HMAC, then the HMAC block stream.
///
/// Panics if the bytes do not contain a well-formed outer header; tests only
/// call this on committed known-good fixtures.
pub fn find_inner_header_start(bytes: &[u8]) -> usize {
    let mut pos = VERSION_HEADER_SIZE;
    loop {
        assert!(
            pos + 5 <= bytes.len(),
            "fixture truncated before HEADER_END at pos {}",
            pos
        );
        let entry_type = bytes[pos];
        let entry_length = u32::from_le_bytes([
            bytes[pos + 1],
            bytes[pos + 2],
            bytes[pos + 3],
            bytes[pos + 4],
        ]) as usize;
        pos += 5 + entry_length;
        if entry_type == HEADER_END {
            return pos;
        }
    }
}

/// Locate the byte offset of a specific outer-header entry_type field.
///
/// Returns the offset of the entry_type byte itself (not the entry_buffer).
/// Returns None if the entry is not found before HEADER_END.
pub fn find_outer_header_entry(bytes: &[u8], target_entry_type: u8) -> Option<usize> {
    let mut pos = VERSION_HEADER_SIZE;
    loop {
        if pos + 5 > bytes.len() {
            return None;
        }
        let entry_type = bytes[pos];
        let entry_length = u32::from_le_bytes([
            bytes[pos + 1],
            bytes[pos + 2],
            bytes[pos + 3],
            bytes[pos + 4],
        ]) as usize;
        if entry_type == target_entry_type {
            return Some(pos);
        }
        if entry_type == HEADER_END {
            return None;
        }
        pos += 5 + entry_length;
    }
}

/// Return a copy of `src` with `patch` overwriting bytes starting at `offset`.
pub fn mutate_bytes(src: &[u8], offset: usize, patch: &[u8]) -> Vec<u8> {
    let mut out = src.to_vec();
    out[offset..offset + patch.len()].copy_from_slice(patch);
    out
}
