use aes::Aes256;
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
use cipher::BlockEncryptMut;
use cipher::{block_padding::Pkcs7, generic_array::GenericArray, BlockDecryptMut};
use salsa20::{
    cipher::{KeyIvInit, StreamCipher},
    Salsa20,
};

use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::crypt::CryptographyError;

pub(crate) trait Cipher {
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, CryptographyError>;
    fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, CryptographyError>;

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    /// The number of bytes expected by the cipher as an initialization vector.
    fn iv_size() -> usize
    where
        Self: Sized;

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    /// The number of bytes expected by the cipher as a key.
    fn key_size() -> usize
    where
        Self: Sized;
}

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
type Aes256CbcEncryptor = cbc::Encryptor<Aes256>;
type Aes256CbcDecryptor = cbc::Decryptor<Aes256>;
#[derive(Zeroize, ZeroizeOnDrop)]
pub(crate) struct AES256Cipher {
    key: Vec<u8>,
    iv: Vec<u8>,
}

impl AES256Cipher {
    pub(crate) fn new(key: &[u8], iv: &[u8]) -> Result<Self, CryptographyError> {
        Ok(AES256Cipher {
            key: Vec::from(key),
            iv: Vec::from(iv),
        })
    }
}

impl Cipher for AES256Cipher {
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        let cipher = Aes256CbcEncryptor::new_from_slices(&self.key, &self.iv)?;

        let ciphertext = cipher.encrypt_padded_vec_mut::<Pkcs7>(plaintext);

        Ok(ciphertext)
    }
    fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        let mut out = vec![0; ciphertext.len()];

        let cipher = Aes256CbcDecryptor::new_from_slices(&self.key[..], &self.iv[..])?;

        let len = cipher
            .decrypt_padded_b2b_mut::<Pkcs7>(ciphertext, &mut out)?
            .len();

        out.truncate(len);

        Ok(out)
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn iv_size() -> usize {
        16
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn key_size() -> usize {
        32
    }
}

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
type TwofishCbcEncryptor = cbc::Encryptor<twofish::Twofish>;
type TwofishCbcDecryptor = cbc::Decryptor<twofish::Twofish>;
#[derive(Zeroize, ZeroizeOnDrop)]
pub(crate) struct TwofishCipher {
    key: Vec<u8>,
    iv: Vec<u8>,
}

impl TwofishCipher {
    pub(crate) fn new(key: &[u8], iv: &[u8]) -> Result<Self, CryptographyError> {
        Ok(TwofishCipher {
            key: Vec::from(key),
            iv: Vec::from(iv),
        })
    }
}

impl Cipher for TwofishCipher {
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        let cipher = TwofishCbcEncryptor::new_from_slices(&self.key, &self.iv)?;

        let ciphertext = cipher.encrypt_padded_vec_mut::<twofish::cipher::block_padding::Pkcs7>(plaintext);

        Ok(ciphertext)
    }

    fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        let cipher = TwofishCbcDecryptor::new_from_slices(&self.key, &self.iv)?;

        let mut buf = ciphertext.to_vec();
        let len = cipher
            .decrypt_padded_mut::<twofish::cipher::block_padding::Pkcs7>(&mut buf)?
            .len();
        buf.truncate(len);
        Ok(buf)
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn iv_size() -> usize {
        16
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn key_size() -> usize {
        32
    }
}

#[derive(ZeroizeOnDrop)]
pub(crate) struct Salsa20Cipher {
    cipher: salsa20::Salsa20,
}

/// Fixed IV of the Salsa20 inner random stream (KeePass `CryptoRandomStream`).
const SALSA20_INNER_STREAM_IV: [u8; 8] = [0xE8, 0x30, 0x09, 0x4B, 0x97, 0x20, 0x5D, 0x2A];

impl Salsa20Cipher {
    /// Create as an inner cipher from the protected stream key, which may be
    /// any length. As in KeePass and KeePassXC, the Salsa20 key is the
    /// SHA-256 of the stream key, for both KDBX3 and KDBX4.
    pub(crate) fn new(key: &[u8]) -> Result<Self, CryptographyError> {
        let mut key = crate::crypt::calculate_sha256(&[key]);
        let cipher = Salsa20::new_from_slices(&key, &SALSA20_INNER_STREAM_IV);
        key.as_mut_slice().zeroize();

        Ok(Salsa20Cipher { cipher: cipher? })
    }
}

impl Cipher for Salsa20Cipher {
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        let mut buffer = Vec::from(plaintext);
        self.cipher.apply_keystream(&mut buffer);
        Ok(buffer)
    }
    fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        let mut buffer = Vec::from(ciphertext);
        self.cipher.apply_keystream(&mut buffer);
        Ok(buffer)
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn iv_size() -> usize {
        // or 16
        32
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn key_size() -> usize {
        32
    }
}

#[derive(ZeroizeOnDrop)]
pub(crate) struct ChaCha20Cipher {
    cipher: chacha20::ChaCha20,
}

impl ChaCha20Cipher {
    /// Create as an inner cipher from the protected stream key: as in KeePass
    /// and KeePassXC, the key and nonce are the first 32 and next 12 bytes of
    /// the SHA-512 of the stream key, for both KDBX3 and KDBX4.
    pub(crate) fn new(key: &[u8]) -> Result<Self, CryptographyError> {
        let iv = crate::crypt::calculate_sha512(&[key]);

        let key = GenericArray::from_slice(&iv[0..32]);
        let nonce = GenericArray::from_slice(&iv[32..44]);

        Ok(ChaCha20Cipher {
            cipher: chacha20::ChaCha20::new(key, nonce),
        })
    }

    /// Create as an outer cipher by separately-specified key and iv
    pub(crate) fn new_key_iv(key: &[u8], iv: &[u8]) -> Result<Self, CryptographyError> {
        Ok(ChaCha20Cipher {
            cipher: chacha20::ChaCha20::new_from_slices(key, iv)?,
        })
    }
}

impl Cipher for ChaCha20Cipher {
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        let mut buffer = Vec::from(plaintext);
        self.cipher.apply_keystream(&mut buffer);
        Ok(buffer)
    }
    fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        let mut buffer = Vec::from(ciphertext);
        self.cipher.apply_keystream(&mut buffer);
        Ok(buffer)
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn iv_size() -> usize {
        12
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn key_size() -> usize {
        32
    }
}

pub(crate) struct PlainCipher;
impl PlainCipher {
    pub(crate) fn new(_: &[u8]) -> Result<Self, CryptographyError> {
        Ok(PlainCipher)
    }
}
impl Cipher for PlainCipher {
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn encrypt(&mut self, plaintext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        Ok(Vec::from(plaintext))
    }
    fn decrypt(&mut self, ciphertext: &[u8]) -> Result<Vec<u8>, CryptographyError> {
        Ok(Vec::from(ciphertext))
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn iv_size() -> usize {
        1
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn key_size() -> usize {
        1
    }
}

/// Inner random stream derivations as specified by KeePass
/// (`CryptoRandomStream`) and KeePassXC (`KeePass2RandomStream::init`),
/// written out independently of the cipher wrappers above.
#[cfg(test)]
pub(crate) mod reference {
    use super::{Cipher, SALSA20_INNER_STREAM_IV};
    use salsa20::cipher::{KeyIvInit, StreamCipher};

    /// Salsa20 keyed with SHA-256(stream key) and the fixed IV.
    pub(crate) fn salsa20_keystream(stream_key: &[u8], len: usize) -> Vec<u8> {
        let key = crate::crypt::calculate_sha256(&[stream_key]);
        let mut cipher = salsa20::Salsa20::new_from_slices(&key, &SALSA20_INNER_STREAM_IV).unwrap();
        let mut keystream = vec![0u8; len];
        cipher.apply_keystream(&mut keystream);
        keystream
    }

    /// ChaCha20 with key and nonce split from SHA-512(stream key).
    pub(crate) fn chacha20_keystream(stream_key: &[u8], len: usize) -> Vec<u8> {
        let hash = crate::crypt::calculate_sha512(&[stream_key]);
        let mut cipher = chacha20::ChaCha20::new_from_slices(&hash[0..32], &hash[32..44]).unwrap();
        let mut keystream = vec![0u8; len];
        cipher.apply_keystream(&mut keystream);
        keystream
    }

    /// The next `len` keystream bytes of `cipher`.
    pub(crate) fn keystream(cipher: &mut dyn Cipher, len: usize) -> Vec<u8> {
        cipher.decrypt(&vec![0u8; len]).unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::reference::{
        chacha20_keystream as reference_chacha20_keystream, keystream,
        salsa20_keystream as reference_salsa20_keystream,
    };
    use super::{Salsa20Cipher, SALSA20_INNER_STREAM_IV};
    use salsa20::cipher::{KeyIvInit, StreamCipher};

    #[test]
    fn salsa20_inner_stream_key_is_sha256_of_stream_key() {
        let stream_key: Vec<u8> = (0u8..32).collect();
        let mut cipher = Salsa20Cipher::new(&stream_key).unwrap();
        assert_eq!(
            keystream(&mut cipher, 100),
            reference_salsa20_keystream(&stream_key, 100)
        );

        // Using the stream key directly as the Salsa20 key is what this
        // crate used to do for KDBX4; make sure that is not what happens.
        let mut raw = salsa20::Salsa20::new_from_slices(&stream_key, &SALSA20_INNER_STREAM_IV).unwrap();
        let mut raw_keystream = vec![0u8; 100];
        raw.apply_keystream(&mut raw_keystream);
        assert_ne!(reference_salsa20_keystream(&stream_key, 100), raw_keystream);
    }

    #[test]
    fn salsa20_cipher_new_accepts_any_stream_key_length() {
        // KeePass hashes the stream key, so its length is not constrained.
        for len in [0usize, 16, 32, 64] {
            let stream_key = vec![0x5Au8; len];
            let mut cipher = Salsa20Cipher::new(&stream_key).unwrap();
            assert_eq!(
                keystream(&mut cipher, 64),
                reference_salsa20_keystream(&stream_key, 64)
            );
        }
    }

    #[test]
    fn chacha20_inner_stream_key_is_split_from_sha512_of_stream_key() {
        let stream_key: Vec<u8> = (0u8..64).collect();
        let mut cipher = super::ChaCha20Cipher::new(&stream_key).unwrap();
        assert_eq!(
            keystream(&mut cipher, 100),
            reference_chacha20_keystream(&stream_key, 100)
        );
    }

    #[test]
    fn inner_cipher_config_uses_reference_derivation() {
        // `InnerCipherConfig::get_cipher` is what the KDBX3 and KDBX4
        // readers and writers call with the protected stream key.
        use crate::config::InnerCipherConfig;

        let stream_key = [0xC3u8; 32];
        let mut salsa20 = InnerCipherConfig::Salsa20.get_cipher(&stream_key).unwrap();
        assert_eq!(
            keystream(&mut *salsa20, 64),
            reference_salsa20_keystream(&stream_key, 64)
        );

        let mut chacha20 = InnerCipherConfig::ChaCha20.get_cipher(&stream_key).unwrap();
        assert_eq!(
            keystream(&mut *chacha20, 64),
            reference_chacha20_keystream(&stream_key, 64)
        );
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    #[test]
    fn twofish_cipher_decrypt_strips_pkcs7_padding() {
        use super::{Cipher, TwofishCipher};

        let key = [0x11u8; 32];
        let iv = [0x22u8; 16];
        let plaintext = b"hello world, this is not block-aligned";

        let mut encryptor = TwofishCipher::new(&key, &iv).unwrap();
        let ciphertext = encryptor.encrypt(plaintext).unwrap();

        let mut decryptor = TwofishCipher::new(&key, &iv).unwrap();
        let decrypted = decryptor.decrypt(&ciphertext).unwrap();

        assert_eq!(decrypted, plaintext);
    }
}
