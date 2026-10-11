use flate2::read::GzDecoder;
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
use flate2::write::GzEncoder;
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
use flate2::Compression as Flate2Compression;
use std::io::Read;
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
use std::io::Write;

pub trait Compression {
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn compress(&self, in_buffer: &[u8]) -> Result<Vec<u8>, std::io::Error>;
    fn decompress(&self, in_buffer: &[u8]) -> Result<Vec<u8>, std::io::Error>;
}

pub struct NoCompression;

impl Compression for NoCompression {
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn compress(&self, in_buffer: &[u8]) -> Result<Vec<u8>, std::io::Error> {
        Ok(in_buffer.to_vec())
    }
    fn decompress(&self, in_buffer: &[u8]) -> Result<Vec<u8>, std::io::Error> {
        Ok(in_buffer.to_vec())
    }
}

pub struct GZipCompression;

/// Cap on decompressed gzip output size. The compressed payload sits inside
/// the already HMAC-authenticated/decrypted KDBX body, so this guards against
/// a post-auth gzip-bomb DoS (a genuinely-keyed but malicious database)
/// rather than a pre-auth attack. Generous enough for any real vault export.
const MAX_DECOMPRESSED_SIZE: u64 = 512 * 1024 * 1024;

impl Compression for GZipCompression {
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn compress(&self, in_buffer: &[u8]) -> Result<Vec<u8>, std::io::Error> {
        let mut res = Vec::new();
        let mut encoder = GzEncoder::new(&mut res, Flate2Compression::default());
        encoder.write_all(in_buffer)?;
        encoder.flush()?;
        encoder.finish()?;
        Ok(res)
    }
    fn decompress(&self, in_buffer: &[u8]) -> Result<Vec<u8>, std::io::Error> {
        decompress_with_limit(in_buffer, MAX_DECOMPRESSED_SIZE)
    }
}

fn decompress_with_limit(in_buffer: &[u8], limit: u64) -> Result<Vec<u8>, std::io::Error> {
    let mut res = Vec::new();
    let decoder = GzDecoder::new(in_buffer);
    // Read one byte past the cap so we can distinguish "exactly at the
    // cap" from "exceeds it" instead of silently truncating the output.
    let mut limited = decoder.take(limit + 1);
    limited.read_to_end(&mut res)?;
    if res.len() as u64 > limit {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "gzip-decompressed payload exceeds maximum allowed size",
        ));
    }
    Ok(res)
}

#[cfg(test)]
mod tests {
    use super::*;
    // Already in scope through `super::*` when a save feature is enabled.
    #[allow(unused_imports)]
    use std::io::Write as _;

    fn gzip(data: &[u8]) -> Vec<u8> {
        let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        encoder.write_all(data).unwrap();
        encoder.finish().unwrap()
    }

    #[test]
    fn decompress_within_limit_succeeds() {
        let plaintext = vec![0u8; 1000];
        let compressed = gzip(&plaintext);
        let out = decompress_with_limit(&compressed, 1000).unwrap();
        assert_eq!(out, plaintext);
    }

    #[test]
    fn decompress_exactly_at_limit_succeeds() {
        let plaintext = vec![b'a'; 500];
        let compressed = gzip(&plaintext);
        let out = decompress_with_limit(&compressed, 500).unwrap();
        assert_eq!(out, plaintext);
    }

    #[test]
    fn decompress_exceeding_limit_errors_instead_of_allocating_unbounded() {
        // Highly compressible: a tiny compressed payload expands far past
        // the limit, the same shape as a real gzip bomb.
        let plaintext = vec![0u8; 10_000_000];
        let compressed = gzip(&plaintext);
        let err = decompress_with_limit(&compressed, 1_000_000).unwrap_err();
        assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
    }

    #[test]
    fn gzip_compression_decompress_rejects_output_over_configured_cap() {
        let plaintext = vec![0u8; (MAX_DECOMPRESSED_SIZE as usize) + 1];
        let compressed = gzip(&plaintext);
        let err = GZipCompression.decompress(&compressed).unwrap_err();
        assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
    }
}
