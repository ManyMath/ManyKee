use aes::Aes256;
use cipher::{
    generic_array::{typenum::U32, GenericArray},
    BlockEncrypt, KeyInit,
};
use sha2::{Digest, Sha256};

use super::CryptographyError;

pub(crate) trait Kdf {
    fn transform_key(
        &self,
        composite_key: &GenericArray<u8, U32>,
    ) -> Result<GenericArray<u8, U32>, CryptographyError>;
}

pub struct AesKdf {
    pub seed: Vec<u8>,
    pub rounds: u64,
}

impl Kdf for AesKdf {
    fn transform_key(
        &self,
        composite_key: &GenericArray<u8, U32>,
    ) -> Result<GenericArray<u8, U32>, CryptographyError> {
        let cipher = Aes256::new_from_slice(&self.seed)?;
        let mut block1 = GenericArray::clone_from_slice(&composite_key[..16]);
        let mut block2 = GenericArray::clone_from_slice(&composite_key[16..]);
        for _ in 0..self.rounds {
            cipher.encrypt_block(&mut block1);
            cipher.encrypt_block(&mut block2);
        }

        let mut digest = Sha256::new();

        digest.update(block1);
        digest.update(block2);

        Ok(digest.finalize())
    }
}

pub struct Argon2Kdf {
    pub memory: u64,
    pub salt: Vec<u8>,
    pub iterations: u64,
    pub parallelism: u32,
    pub version: argon2::Version,
    pub variant: argon2::Variant,
}

impl Kdf for Argon2Kdf {
    fn transform_key(
        &self,
        composite_key: &GenericArray<u8, U32>,
    ) -> Result<GenericArray<u8, U32>, CryptographyError> {
        // Disable Argon2 multithreading on wasm32 targets to avoid panics on platforms without thread support.
        let thread_mode = if cfg!(target_arch = "wasm32") {
            argon2::ThreadMode::Sequential
        } else {
            argon2::ThreadMode::Parallel
        };

        let config = argon2::Config {
            thread_mode,
            ad: &[],
            hash_length: 32,
            lanes: self.parallelism,
            mem_cost: (self.memory / 1024) as u32,
            secret: &[],
            time_cost: self.iterations as u32,
            variant: self.variant,
            version: self.version,
        };

        let key = argon2::hash_raw(composite_key, &self.salt, &config)?;

        Ok(*GenericArray::from_slice(&key))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aes_kdf_rejects_wrong_length_seed() {
        // The seed comes straight from the untrusted header's KDF variant
        // dictionary; it must not panic when its length isn't exactly 32
        // bytes (AES-256's key size).
        for len in [0, 16, 31, 33, 64] {
            let kdf = AesKdf {
                seed: vec![0u8; len],
                rounds: 1,
            };
            let composite_key = GenericArray::default();
            assert!(
                kdf.transform_key(&composite_key).is_err(),
                "expected error for seed length {}",
                len
            );
        }
    }

    #[test]
    fn aes_kdf_accepts_correct_length_seed() {
        let kdf = AesKdf {
            seed: vec![0u8; 32],
            rounds: 1,
        };
        let composite_key = GenericArray::default();
        assert!(kdf.transform_key(&composite_key).is_ok());
    }
}
