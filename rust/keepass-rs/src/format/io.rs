use std::convert::TryFrom;
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
use std::io::Write;

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
use byteorder::{LittleEndian, WriteBytesExt};

/// Extension trait to write a length-tagged field
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
pub trait WriteLengthTaggedExt: Write {
    fn write_with_len(&mut self, data: &[u8]) -> Result<(), std::io::Error> {
        self.write_u32::<LittleEndian>(data.len() as u32)?;
        self.write_all(data)?;
        Ok(())
    }
}

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
impl<W: Write + ?Sized> WriteLengthTaggedExt for W {}

/// Decodes a little-endian `u32` from a buffer that must be exactly 4 bytes.
///
/// Header entry buffers are sized by a length field read from the file, so a
/// fixed-width field can arrive shorter than its type requires. `byteorder`
/// panics on such a buffer; this returns `None` so the caller can report it.
pub(crate) fn read_le_u32_exact(buf: &[u8]) -> Option<u32> {
    <[u8; 4]>::try_from(buf).ok().map(u32::from_le_bytes)
}

/// Decodes a little-endian `u64` from a buffer that must be exactly 8 bytes.
/// See [`read_le_u32_exact`].
pub(crate) fn read_le_u64_exact(buf: &[u8]) -> Option<u64> {
    <[u8; 8]>::try_from(buf).ok().map(u64::from_le_bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_readers_reject_short_and_long_buffers() {
        assert_eq!(read_le_u32_exact(&[1, 0, 0, 0]), Some(1));
        assert_eq!(read_le_u32_exact(&[1, 0, 0]), None);
        assert_eq!(read_le_u32_exact(&[]), None);
        assert_eq!(read_le_u32_exact(&[1, 0, 0, 0, 0]), None);

        assert_eq!(read_le_u64_exact(&[2, 0, 0, 0, 0, 0, 0, 0]), Some(2));
        assert_eq!(read_le_u64_exact(&[2, 0, 0, 0, 0, 0, 0]), None);
        assert_eq!(read_le_u64_exact(&[2, 0, 0, 0]), None);
    }
}
