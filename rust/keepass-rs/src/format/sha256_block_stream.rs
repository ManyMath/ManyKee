//! Writer for the plain SHA256 block-hashed stream format used by KDBX3.
//!
//! This is the writer counterpart to the inline reader in
//! `format::kdbx3::decrypt_kdbx3`: each block is `block_id: u32 LE`,
//! `block_hash: [u8; 32]` (SHA256 of the block data), `block_size: u32 LE`,
//! then the block data, terminated by a zero-size block whose hash field is
//! all zeros (KeePass and KeePassXC reject any other terminator hash).

use byteorder::{LittleEndian, WriteBytesExt};

use crate::crypt::calculate_sha256;

/// Write a raw buffer as a SHA256 block-hashed stream (KDBX3 payload format)
pub(crate) fn write_sha256_block_stream(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();

    write_block(&mut out, 0, data, &calculate_sha256(&[data]));
    write_block(&mut out, 1, &[], &[0u8; 32]);

    out
}

fn write_block(out: &mut Vec<u8>, block_id: u32, block: &[u8], block_hash: &[u8]) {
    out.write_u32::<LittleEndian>(block_id)
        .expect("write to Vec cannot fail");
    out.extend_from_slice(block_hash);
    out.write_u32::<LittleEndian>(block.len() as u32)
        .expect("write to Vec cannot fail");
    out.extend_from_slice(block);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminating_block_has_zero_hash() {
        let out = write_sha256_block_stream(b"payload");
        let terminator = &out[out.len() - 40..];

        assert_eq!(&terminator[0..4], &1u32.to_le_bytes());
        assert_eq!(&terminator[4..36], &[0u8; 32]);
        assert_eq!(&terminator[36..40], &0u32.to_le_bytes());
    }

    #[test]
    fn data_block_hash_covers_the_data() {
        let out = write_sha256_block_stream(b"payload");

        assert_eq!(&out[4..36], calculate_sha256(&[b"payload"]).as_slice());
    }
}
