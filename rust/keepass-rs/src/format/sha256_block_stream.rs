//! Writer for the plain SHA256 block-hashed stream format used by KDBX3.
//!
//! This is the writer counterpart to the inline reader in
//! `format::kdbx3::decrypt_kdbx3`: each block is `block_id: u32 LE`,
//! `block_hash: [u8; 32]` (SHA256 of the block data), `block_size: u32 LE`,
//! then the block data, terminated by a zero-size block.

use byteorder::{LittleEndian, WriteBytesExt};

use crate::crypt::calculate_sha256;

/// Write a raw buffer as a SHA256 block-hashed stream (KDBX3 payload format)
pub(crate) fn write_sha256_block_stream(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();

    write_block(&mut out, 0, data);
    write_block(&mut out, 1, &[]);

    out
}

fn write_block(out: &mut Vec<u8>, block_id: u32, block: &[u8]) {
    let block_hash = calculate_sha256(&[block]);

    out.write_u32::<LittleEndian>(block_id).expect("write to Vec cannot fail");
    out.extend_from_slice(&block_hash);
    out.write_u32::<LittleEndian>(block.len() as u32)
        .expect("write to Vec cannot fail");
    out.extend_from_slice(block);
}
