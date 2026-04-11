#[cfg(feature = "challenge_response")]
use cipher::generic_array::typenum::U20;
use cipher::{
    block_padding::UnpadError,
    generic_array::{
        typenum::{U32, U64},
        GenericArray,
    },
    InvalidLength,
};

use hmac::{Hmac, Mac};
#[cfg(feature = "challenge_response")]
use sha1::Sha1;
use sha2::{Digest, Sha256, Sha512};
use thiserror::Error;

pub(crate) mod ciphers;
pub(crate) mod kdf;

/// Compare two byte slices for equality in constant time, for comparisons
/// where non-constant-time `!=` would leak timing information about secret
/// or key-derived data (MAC tags, decryption-correctness markers). Lengths
/// are compared first (not constant-time), which is fine here since none of
/// this crate's callers treat length itself as secret.
pub(crate) fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    use subtle::ConstantTimeEq;
    a.ct_eq(b).into()
}

pub(crate) fn calculate_hmac(elements: &[&[u8]], key: &[u8]) -> Result<GenericArray<u8, U32>, InvalidLength> {
    type HmacSha256 = Hmac<Sha256>;
    let mut mac = HmacSha256::new_from_slice(key)?;

    for element in elements {
        mac.update(element);
    }

    let result = mac.finalize();
    Ok(result.into_bytes())
}

#[cfg(feature = "challenge_response")]
pub(crate) fn calculate_hmac_sha1(
    elements: &[&[u8]],
    key: &[u8],
) -> Result<GenericArray<u8, U20>, InvalidLength> {
    type HmacSha1 = Hmac<Sha1>;
    let mut mac = HmacSha1::new_from_slice(key)?;

    for element in elements {
        mac.update(element);
    }

    let result = mac.finalize();
    Ok(result.into_bytes())
}

pub(crate) fn calculate_sha256(elements: &[&[u8]]) -> GenericArray<u8, U32> {
    let mut digest = Sha256::new();

    for element in elements {
        digest.update(element);
    }

    digest.finalize()
}

pub(crate) fn calculate_sha512(elements: &[&[u8]]) -> GenericArray<u8, U64> {
    let mut digest = Sha512::new();

    for element in elements {
        digest.update(element);
    }

    digest.finalize()
}

#[derive(Error, Debug)]
pub enum CryptographyError {
    #[error(transparent)]
    InvalidLength(#[from] InvalidLength),

    #[error(transparent)]
    InvalidPadding(#[from] UnpadError),

    #[error(transparent)]
    Argon2(#[from] argon2::Error),

    #[error("KDF parameter out of range: {0}")]
    InvalidKdfParameter(&'static str),
}

#[cfg(test)]
mod tests {
    use super::constant_time_eq;

    #[test]
    fn constant_time_eq_matches_equal_slices() {
        assert!(constant_time_eq(b"same bytes", b"same bytes"));
    }

    #[test]
    fn constant_time_eq_rejects_different_content() {
        assert!(!constant_time_eq(b"AAAAAAAAAA", b"AAAAAAAAAB"));
    }

    #[test]
    fn constant_time_eq_rejects_different_length() {
        assert!(!constant_time_eq(b"short", b"much longer input"));
    }
}
