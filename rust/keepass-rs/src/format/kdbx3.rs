#[cfg(feature = "save_kdbx3")]
use std::io::Write;

use crate::{
    config::{CompressionConfig, DatabaseConfig, InnerCipherConfig, KdfConfig, OuterCipherConfig},
    crypt::{calculate_sha256, ciphers::Cipher},
    db::{Database, DatabaseFormatError, DatabaseOpenError},
    format::{
        io::{read_le_u32_exact, read_le_u64_exact},
        DatabaseVersion,
    },
    key::{DatabaseKey, DatabaseKeyError},
};

#[cfg(feature = "save_kdbx3")]
use crate::db::DatabaseSaveError;

#[cfg(feature = "save_kdbx3")]
use byteorder::WriteBytesExt;
use byteorder::{ByteOrder, LittleEndian};
use thiserror::Error;

use std::convert::TryFrom;

// Outer header entry type identifiers, shared by the reader
// (`parse_outer_header`) and the writer (`dump_kdbx3`).
const HEADER_END: u8 = 0;
const HEADER_COMMENT: u8 = 1;
const HEADER_OUTER_ENCRYPTION_ID: u8 = 2;
const HEADER_COMPRESSION_ID: u8 = 3;
const HEADER_MASTER_SEED: u8 = 4;
const HEADER_TRANSFORM_SEED: u8 = 5;
const HEADER_TRANSFORM_ROUNDS: u8 = 6;
const HEADER_ENCRYPTION_IV: u8 = 7;
const HEADER_PROTECTED_STREAM_KEY: u8 = 8;
const HEADER_STREAM_START_BYTES: u8 = 9;
const HEADER_INNER_RANDOM_STREAM_ID: u8 = 10;

/// Size (in bytes) of the master seed, transform seed, protected stream key
/// and stream start marker generated when writing a KDBX3 file.
#[cfg(feature = "save_kdbx3")]
const KDBX3_RANDOM_FIELD_SIZE: usize = 32;

#[derive(Debug)]
struct KDBX3Header {
    // https://gist.github.com/msmuenchen/9318327
    outer_cipher: OuterCipherConfig,
    compression: CompressionConfig,
    master_seed: Vec<u8>,

    transform_seed: Vec<u8>,
    kdf_config: KdfConfig,

    outer_iv: Vec<u8>,
    protected_stream_key: zeroize::Zeroizing<Vec<u8>>,
    stream_start: Vec<u8>,
    inner_cipher: InnerCipherConfig,
    body_start: usize,
}

fn parse_outer_header(data: &[u8]) -> Result<KDBX3Header, Kdbx3OuterHeaderError> {
    let mut outer_cipher: Option<OuterCipherConfig> = None;
    let mut compression: Option<CompressionConfig> = None;
    let mut master_seed: Option<Vec<u8>> = None;
    let mut transform_seed: Option<Vec<u8>> = None;
    let mut transform_rounds: Option<u64> = None;
    let mut outer_iv: Option<Vec<u8>> = None;
    let mut protected_stream_key: Option<zeroize::Zeroizing<Vec<u8>>> = None;
    let mut stream_start: Option<Vec<u8>> = None;
    let mut inner_cipher: Option<InnerCipherConfig> = None;

    // skip over the version header
    let mut pos = DatabaseVersion::get_version_header_size();

    // parse header
    loop {
        // parse header blocks.
        //
        // every block is a triplet of (3 + entry_length) bytes with this structure:
        //
        // (
        // entry_type: u8, // a numeric entry type identifier
        // entry_length: u16, // length of the entry buffer
        // entry_buffer: [u8; entry_length] // the entry buffer
        // )

        let entry_type = *data.get(pos).ok_or(Kdbx3OuterHeaderError::UnexpectedEof)?;
        let entry_length: usize = LittleEndian::read_u16(
            data.get((pos + 1)..(pos + 3))
                .ok_or(Kdbx3OuterHeaderError::UnexpectedEof)?,
        ) as usize;
        let entry_start = pos + 3;
        let entry_end = entry_start
            .checked_add(entry_length)
            .ok_or(Kdbx3OuterHeaderError::UnexpectedEof)?;
        let entry_buffer = data
            .get(entry_start..entry_end)
            .ok_or(Kdbx3OuterHeaderError::UnexpectedEof)?;

        pos = entry_end;

        match entry_type {
            // END - finished parsing header
            HEADER_END => {
                break;
            }

            // COMMENT
            HEADER_COMMENT => {}

            // CIPHERID - a UUID specifying which cipher suite
            // should be used to encrypt the payload
            HEADER_OUTER_ENCRYPTION_ID => {
                outer_cipher = Some(OuterCipherConfig::try_from(entry_buffer)?);
            }

            // COMPRESSIONFLAGS - first byte determines compression of payload
            HEADER_COMPRESSION_ID => {
                let compression_id =
                    read_le_u32_exact(entry_buffer).ok_or(Kdbx3OuterHeaderError::InvalidEntryLength {
                        entry_type,
                        expected: 4,
                        actual: entry_buffer.len(),
                    })?;
                compression = Some(CompressionConfig::try_from(compression_id)?);
            }

            // MASTERSEED - Master seed for deriving the master key
            HEADER_MASTER_SEED => master_seed = Some(entry_buffer.to_vec()),

            // TRANSFORMSEED - Seed used in deriving the transformed key
            HEADER_TRANSFORM_SEED => transform_seed = Some(entry_buffer.to_vec()),

            // TRANSFORMROUNDS - Number of rounds used in derivation of transformed key
            HEADER_TRANSFORM_ROUNDS => {
                transform_rounds = Some(read_le_u64_exact(entry_buffer).ok_or(
                    Kdbx3OuterHeaderError::InvalidEntryLength {
                        entry_type,
                        expected: 8,
                        actual: entry_buffer.len(),
                    },
                )?)
            }

            // ENCRYPTIONIV - Initialization Vector for decrypting the payload
            HEADER_ENCRYPTION_IV => outer_iv = Some(entry_buffer.to_vec()),

            // PROTECTEDSTREAMKEY - Key for decrypting the inner protected values
            HEADER_PROTECTED_STREAM_KEY => {
                protected_stream_key = Some(zeroize::Zeroizing::new(entry_buffer.to_vec()))
            }

            // STREAMSTARTBYTES - First bytes of decrypted payload (to check correct decryption)
            HEADER_STREAM_START_BYTES => stream_start = Some(entry_buffer.to_vec()),

            // INNERRANDOMSTREAMID - specifies which cipher suite
            // to use for decrypting the inner protected values
            HEADER_INNER_RANDOM_STREAM_ID => {
                let stream_id =
                    read_le_u32_exact(entry_buffer).ok_or(Kdbx3OuterHeaderError::InvalidEntryLength {
                        entry_type,
                        expected: 4,
                        actual: entry_buffer.len(),
                    })?;
                inner_cipher = Some(InnerCipherConfig::try_from(stream_id)?);
            }

            _ => {
                return Err(Kdbx3OuterHeaderError::InvalidOuterHeaderEntry(entry_type));
            }
        };
    }

    // at this point, the header needs to be fully defined - unwrap options and return errors if
    // something is missing

    fn get_or_err<T>(v: Option<T>, err: &'static str) -> Result<T, Kdbx3OuterHeaderError> {
        v.ok_or(Kdbx3OuterHeaderError::IncompleteOuterHeader(err))
    }

    let outer_cipher = get_or_err(outer_cipher, "Outer Cipher ID")?;
    let compression = get_or_err(compression, "Compression ID")?;
    let master_seed = get_or_err(master_seed, "Master seed")?;
    let transform_seed = get_or_err(transform_seed, "Transform seed")?;
    let transform_rounds = get_or_err(transform_rounds, "Number of transformation rounds")?;
    let outer_iv = get_or_err(outer_iv, "Outer cipher IV")?;
    let protected_stream_key = get_or_err(protected_stream_key, "Protected stream key")?;
    let stream_start = get_or_err(stream_start, "Stream start bytes")?;
    let inner_cipher = get_or_err(inner_cipher, "Inner cipher ID")?;

    crate::config::validate_aes_kdf_rounds(transform_rounds)?;

    // KDF type is always AES for KDBX3
    let kdf_config = KdfConfig::Aes {
        rounds: transform_rounds,
    };

    Ok(KDBX3Header {
        outer_cipher,
        compression,
        master_seed,
        transform_seed,
        kdf_config,
        outer_iv,
        protected_stream_key,
        stream_start,
        inner_cipher,
        body_start: pos,
    })
}

#[derive(Debug, Error)]
pub enum Kdbx3OuterHeaderError {
    #[error("Unexpected end of file while parsing outer header")]
    UnexpectedEof,

    #[error(transparent)]
    InnerCipher(#[from] crate::config::InnerCipherConfigError),

    #[error(transparent)]
    OuterCipher(#[from] crate::config::OuterCipherConfigError),

    #[error(transparent)]
    Compression(#[from] crate::config::CompressionConfigError),

    #[error(transparent)]
    KdfConfig(#[from] crate::config::KdfConfigError),

    #[error("Encountered invalid outer header entry with type {0}")]
    InvalidOuterHeaderEntry(u8),

    #[error("Outer header entry {entry_type} has length {actual}, expected {expected}")]
    InvalidEntryLength {
        entry_type: u8,
        expected: usize,
        actual: usize,
    },

    #[error("Outer header is missing {0}")]
    IncompleteOuterHeader(&'static str),
}

/// Open, decrypt and parse a KeePass database from a source and a password
pub(crate) fn parse_kdbx3(data: &[u8], db_key: &DatabaseKey) -> Result<Database, DatabaseOpenError> {
    let (config, mut inner_decryptor, xml) = decrypt_kdbx3(data, db_key)?;

    // Parse XML data blocks
    let mut db = crate::format::xml_db::parse_xml(&xml, &[], &mut *inner_decryptor)
        .map_err(|e| DatabaseOpenError::Format(DatabaseFormatError::Kdbx3(Kdbx3OpenError::Xml(e))))?;

    db.config = config;

    Ok(db)
}

/// Open and decrypt a KeePass KDBX3 database from a source and a password
#[allow(clippy::type_complexity)]
pub(crate) fn decrypt_kdbx3(
    data: &[u8],
    db_key: &DatabaseKey,
) -> Result<(DatabaseConfig, Box<dyn Cipher>, Vec<u8>), DatabaseOpenError> {
    let version = DatabaseVersion::parse(data)?;
    let header = parse_outer_header(data)
        .map_err(|e| DatabaseOpenError::Format(DatabaseFormatError::Kdbx3(Kdbx3OpenError::OuterHeader(e))))?;

    // Set up decryption of inner protected values. The inner cipher derives
    // its own key from the protected stream key (SHA-256 for Salsa20,
    // SHA-512 for ChaCha20), exactly as for KDBX4, so pass it unhashed.
    let inner_decryptor = header.inner_cipher.get_cipher(&header.protected_stream_key)?;

    let config = DatabaseConfig {
        version,
        outer_cipher_config: header.outer_cipher,
        compression_config: header.compression,
        inner_cipher_config: header.inner_cipher,
        kdf_config: header.kdf_config,
        public_custom_data: Default::default(),
    };

    let mut pos = header.body_start;

    // Turn enums into appropriate trait objects
    let compression = config.compression_config.get_compression();

    // Rest of file after header is payload
    let payload_encrypted = &data[pos..];

    // derive master key from composite key, transform_seed, transform_rounds and master_seed.
    // These are all key-derived secrets with no zeroization otherwise, so each is wrapped in
    // `Zeroizing` to guarantee it's cleared on every exit path, including `?` error returns.
    let key_elements = db_key.get_key_elements()?;
    let key_element_refs: Vec<&[u8]> = key_elements.iter().map(|v| &v[..]).collect();
    let composite_key = zeroize::Zeroizing::new(calculate_sha256(&key_element_refs).to_vec());

    // transform the key
    let transformed_key = zeroize::Zeroizing::new(
        config
            .kdf_config
            .get_kdf_seeded(&header.transform_seed)
            .transform_key(cipher::generic_array::GenericArray::from_slice(&composite_key))?
            .to_vec(),
    );

    let master_key =
        zeroize::Zeroizing::new(calculate_sha256(&[header.master_seed.as_ref(), &transformed_key]).to_vec());

    // Decrypt payload
    let payload = config
        .outer_cipher_config
        .get_cipher(&master_key, header.outer_iv.as_ref())?
        .decrypt(payload_encrypted)?;

    // Check if we decrypted correctly. `stream_start` is attacker-controlled
    // header data, so it may claim a length longer than the decrypted
    // payload; treat that as a failed check rather than panicking.
    let expected_stream_start = &header.stream_start;
    let stream_start_matches = payload
        .get(0..expected_stream_start.len())
        .is_some_and(|start| crate::crypt::constant_time_eq(start, expected_stream_start));
    if !stream_start_matches {
        return Err(DatabaseKeyError::IncorrectKey.into());
    }

    let mut buf = Vec::new();

    pos = 32;
    let mut block_index = 0;
    loop {
        // Parse blocks in payload.
        //
        // Each block is a tuple of size (40 + block_size) with structure:
        //
        // (
        // block_id: u32, // a numeric block ID (starts at 0)
        // block_hash: [u8, 32], // SHA256 of block_buffer_compressed
        // block_size: u32, // block_size size in bytes
        // block_buffer_compressed: [u8, block_size] // Block data, possibly compressed
        // )

        // let block_id = LittleEndian::read_u32(&payload[pos..(pos + 4)]);
        let block_hash = payload
            .get((pos + 4)..(pos + 36))
            .ok_or(DatabaseOpenError::UnexpectedEof)?;
        let block_size = LittleEndian::read_u32(
            payload
                .get((pos + 36)..(pos + 40))
                .ok_or(DatabaseOpenError::UnexpectedEof)?,
        ) as usize;

        // A block with size 0 means we have hit EOF
        if block_size == 0 {
            break;
        }

        // `block_size` is a u32 from the decrypted payload; on 32-bit
        // targets `pos + 40 + block_size` can overflow usize, so compute the
        // end with checked arithmetic.
        let block_start = pos + 40;
        let block_end = block_start
            .checked_add(block_size)
            .ok_or(DatabaseOpenError::UnexpectedEof)?;
        let block_buffer_compressed = payload
            .get(block_start..block_end)
            .ok_or(DatabaseOpenError::UnexpectedEof)?;

        // Test block hash
        let block_hash_check = calculate_sha256(&[block_buffer_compressed]);
        if block_hash != block_hash_check.as_slice() {
            return Err(DatabaseOpenError::Format(DatabaseFormatError::Kdbx3(
                Kdbx3OpenError::BlockHashMismatch(block_index),
            )));
        }

        // Decompress block_buffer_compressed
        buf.append(&mut block_buffer_compressed.to_vec());

        pos = block_end;
        block_index += 1;
    }

    let xml = compression.decompress(&buf)?;

    Ok((config, inner_decryptor, xml))
}

/// Dump a KeePass database using the key elements, in the legacy KDBX3
/// format. Only databases using AES-KDF, and AES256/Twofish outer
/// encryption with a Plain/Salsa20 inner stream cipher can be represented in
/// this format; anything else (Argon2, ChaCha20, public custom data) returns
/// [`DatabaseSaveError::IncompatibleWithVersion`].
#[cfg(feature = "save_kdbx3")]
pub fn dump_kdbx3(
    db: &Database,
    db_key: &DatabaseKey,
    writer: &mut dyn Write,
) -> Result<(), DatabaseSaveError> {
    if !matches!(db.config.version, DatabaseVersion::KDB3(_)) {
        return Err(DatabaseSaveError::UnsupportedVersion);
    }

    let rounds = match &db.config.kdf_config {
        KdfConfig::Aes { rounds } => *rounds,
        _ => {
            return Err(DatabaseSaveError::IncompatibleWithVersion(
                "KDBX3 only supports the AES-KDF key derivation function",
            ))
        }
    };

    if !matches!(
        db.config.outer_cipher_config,
        OuterCipherConfig::AES256 | OuterCipherConfig::Twofish
    ) {
        return Err(DatabaseSaveError::IncompatibleWithVersion(
            "KDBX3 only supports AES256/Twofish outer encryption",
        ));
    }

    if !matches!(
        db.config.inner_cipher_config,
        InnerCipherConfig::Plain | InnerCipherConfig::Salsa20
    ) {
        return Err(DatabaseSaveError::IncompatibleWithVersion(
            "KDBX3 only supports Plain/Salsa20 inner encryption",
        ));
    }

    if db
        .config
        .public_custom_data
        .as_ref()
        .is_some_and(|d| !d.data.is_empty())
    {
        return Err(DatabaseSaveError::IncompatibleWithVersion(
            "KDBX3 has no public custom data header field",
        ));
    }

    // generate encryption keys and seeds on the fly when saving
    let mut master_seed = vec![0; KDBX3_RANDOM_FIELD_SIZE];
    getrandom::getrandom(&mut master_seed)?;

    let mut outer_iv = vec![0; db.config.outer_cipher_config.get_iv_size()];
    getrandom::getrandom(&mut outer_iv)?;

    let mut transform_seed = vec![0; KDBX3_RANDOM_FIELD_SIZE];
    getrandom::getrandom(&mut transform_seed)?;

    let mut protected_stream_key = zeroize::Zeroizing::new(vec![0; KDBX3_RANDOM_FIELD_SIZE]);
    getrandom::getrandom(&mut protected_stream_key)?;

    let mut stream_start = vec![0; KDBX3_RANDOM_FIELD_SIZE];
    getrandom::getrandom(&mut stream_start)?;

    #[cfg(feature = "challenge_response")]
    let db_key = db_key.clone().perform_challenge(&transform_seed)?;

    // dump the outer header
    let mut header_data = Vec::new();
    db.config.version.dump(&mut header_data)?;

    KDBX3OuterHeader {
        outer_cipher: db.config.outer_cipher_config.clone(),
        compression: db.config.compression_config.clone(),
        master_seed: master_seed.clone(),
        transform_seed: transform_seed.clone(),
        rounds,
        outer_iv: outer_iv.clone(),
        protected_stream_key: protected_stream_key.clone(),
        stream_start: stream_start.clone(),
        inner_cipher: db.config.inner_cipher_config.clone(),
    }
    .dump(&mut header_data)?;

    writer.write_all(&header_data)?;

    // derive master key from composite key, transform_seed, rounds and master_seed. These are
    // all key-derived secrets with no zeroization otherwise, so each is wrapped in `Zeroizing`
    // to guarantee it's cleared on every exit path, including `?` error returns.
    let key_elements = db_key.get_key_elements()?;
    let key_element_refs: Vec<&[u8]> = key_elements.iter().map(|v| &v[..]).collect();
    let composite_key = zeroize::Zeroizing::new(calculate_sha256(&key_element_refs).to_vec());

    let transformed_key = zeroize::Zeroizing::new(
        db.config
            .kdf_config
            .get_kdf_seeded(&transform_seed)
            .transform_key(cipher::generic_array::GenericArray::from_slice(&composite_key))?
            .to_vec(),
    );

    let master_key = zeroize::Zeroizing::new(calculate_sha256(&[&master_seed, &transformed_key]).to_vec());

    // Initialize inner encryptor from the protected stream key; the inner
    // cipher hashes it itself (see `decrypt_kdbx3`).
    let mut inner_cipher = db.config.inner_cipher_config.get_cipher(&protected_stream_key)?;

    // convert database to XML, with attachments inlined as Meta/Binaries
    let xml = crate::format::xml_db::to_xml_inline_binaries(db, &mut *inner_cipher)?;

    let xml_compressed = db.config.compression_config.get_compression().compress(&xml)?;

    let mut payload = stream_start;
    payload.extend(crate::format::sha256_block_stream::write_sha256_block_stream(
        &xml_compressed,
    ));

    let payload_encrypted = db
        .config
        .outer_cipher_config
        .get_cipher(&master_key, &outer_iv)?
        .encrypt(&payload)?;

    writer.write_all(&payload_encrypted)?;

    Ok(())
}

/// Fields needed to dump a KDBX3 outer header. Distinct from [`KDBX3Header`]
/// (which additionally tracks where the header ends in a parsed buffer, and
/// is only meaningful when reading).
#[cfg(feature = "save_kdbx3")]
struct KDBX3OuterHeader {
    outer_cipher: OuterCipherConfig,
    compression: CompressionConfig,
    master_seed: Vec<u8>,
    transform_seed: Vec<u8>,
    rounds: u64,
    outer_iv: Vec<u8>,
    protected_stream_key: zeroize::Zeroizing<Vec<u8>>,
    stream_start: Vec<u8>,
    inner_cipher: InnerCipherConfig,
}

#[cfg(feature = "save_kdbx3")]
fn write_kdbx3_header_entry(writer: &mut dyn Write, entry_type: u8, data: &[u8]) -> Result<(), std::io::Error> {
    // Unlike KDBX4 (which length-prefixes header entries with a u32, see
    // `format::io::WriteLengthTaggedExt`), KDBX3 uses a u16 entry length -
    // see the `entry_length` read in `parse_outer_header` above.
    writer.write_u8(entry_type)?;
    writer.write_u16::<LittleEndian>(data.len() as u16)?;
    writer.write_all(data)?;
    Ok(())
}

#[cfg(feature = "save_kdbx3")]
impl KDBX3OuterHeader {
    fn dump(&self, writer: &mut dyn Write) -> Result<(), DatabaseSaveError> {
        write_kdbx3_header_entry(writer, HEADER_OUTER_ENCRYPTION_ID, &self.outer_cipher.dump())?;
        write_kdbx3_header_entry(writer, HEADER_COMPRESSION_ID, &self.compression.dump())?;
        write_kdbx3_header_entry(writer, HEADER_MASTER_SEED, &self.master_seed)?;
        write_kdbx3_header_entry(writer, HEADER_TRANSFORM_SEED, &self.transform_seed)?;

        let mut rounds_bytes = vec![0; 8];
        LittleEndian::write_u64(&mut rounds_bytes, self.rounds);
        write_kdbx3_header_entry(writer, HEADER_TRANSFORM_ROUNDS, &rounds_bytes)?;

        write_kdbx3_header_entry(writer, HEADER_ENCRYPTION_IV, &self.outer_iv)?;
        write_kdbx3_header_entry(writer, HEADER_PROTECTED_STREAM_KEY, &self.protected_stream_key)?;
        write_kdbx3_header_entry(writer, HEADER_STREAM_START_BYTES, &self.stream_start)?;

        let mut inner_cipher_bytes = vec![0; 4];
        LittleEndian::write_u32(&mut inner_cipher_bytes, self.inner_cipher.dump());
        write_kdbx3_header_entry(writer, HEADER_INNER_RANDOM_STREAM_ID, &inner_cipher_bytes)?;

        write_kdbx3_header_entry(writer, HEADER_END, &[])?;

        Ok(())
    }
}

#[derive(Debug, Error)]
pub enum Kdbx3OpenError {
    #[error(transparent)]
    OuterHeader(#[from] Kdbx3OuterHeaderError),

    #[error("block hash mismatch at block index {0}")]
    BlockHashMismatch(usize),

    #[error(transparent)]
    Xml(#[from] crate::format::xml_db::ParseXmlError),
}

#[cfg(feature = "save_kdbx3")]
#[cfg(test)]
mod kdbx3_dump_tests {
    use super::*;

    use crate::{
        db::{fields, Attachment, Database, Entry, Group, Value},
        key::DatabaseKey,
    };

    fn test_config(
        outer_cipher_config: OuterCipherConfig,
        inner_cipher_config: InnerCipherConfig,
        compression_config: CompressionConfig,
    ) -> DatabaseConfig {
        DatabaseConfig {
            version: DatabaseVersion::KDB3(1),
            outer_cipher_config,
            compression_config,
            inner_cipher_config,
            kdf_config: KdfConfig::Aes { rounds: 10 },
            public_custom_data: Default::default(),
        }
    }

    fn test_with_config(config: DatabaseConfig) {
        let mut db = Database::new(config);

        let mut entry_with_password = Entry::new();
        entry_with_password.set_unprotected(fields::TITLE, "Demo Entry");
        entry_with_password.set_protected(fields::PASSWORD, "secret");

        entry_with_password.attachments.insert(
            "file1.txt".into(),
            Attachment {
                data: Value::protected(vec![0x01, 0x02, 0x03, 0x04]),
            },
        );
        entry_with_password.attachments.insert(
            "file2.txt".into(),
            Attachment {
                data: Value::unprotected(vec![0x04, 0x03, 0x02, 0x01]),
            },
        );

        let mut root_group = Group::new("Root");
        root_group.entries.push(entry_with_password);
        root_group.entries.push(Entry::new());
        db.root = root_group;

        let db_key = DatabaseKey::new().with_password("testing");

        let mut encrypted_db = Vec::new();
        dump_kdbx3(&db, &db_key, &mut encrypted_db).unwrap();

        let decrypted_db = parse_kdbx3(&encrypted_db, &db_key).unwrap();

        assert_eq!(decrypted_db.root.entries.len(), 2);

        let entry = decrypted_db.root.entry_by_name("Demo Entry").unwrap();
        assert_eq!(entry.get_password(), Some("secret"));

        let attachments = &entry.attachments;
        assert_eq!(attachments.len(), 2);
        assert!(attachments["file1.txt"].is_protected());
        assert_eq!(attachments["file1.txt"].get(), &[0x01, 0x02, 0x03, 0x04]);
        assert!(!attachments["file2.txt"].is_protected());
        assert_eq!(attachments["file2.txt"].get(), &[0x04, 0x03, 0x02, 0x01]);
    }

    #[test]
    fn test_config_matrix() {
        let outer_cipher_configs = [OuterCipherConfig::AES256, OuterCipherConfig::Twofish];
        let inner_cipher_configs = [InnerCipherConfig::Plain, InnerCipherConfig::Salsa20];
        let compression_configs = [CompressionConfig::None, CompressionConfig::GZip];

        for outer_cipher_config in &outer_cipher_configs {
            for inner_cipher_config in &inner_cipher_configs {
                for compression_config in &compression_configs {
                    test_with_config(test_config(
                        outer_cipher_config.clone(),
                        inner_cipher_config.clone(),
                        compression_config.clone(),
                    ));
                }
            }
        }
    }

    /// Range of the value of the first outer header entry with `entry_type`.
    fn header_entry_value_range(data: &[u8], entry_type: u8) -> std::ops::Range<usize> {
        let mut pos = DatabaseVersion::get_version_header_size();
        loop {
            let ty = data[pos];
            let len = LittleEndian::read_u16(&data[pos + 1..pos + 3]) as usize;
            if ty == entry_type {
                return pos + 3..pos + 3 + len;
            }
            assert_ne!(ty, HEADER_END, "header entry {} not found", entry_type);
            pos += 3 + len;
        }
    }

    #[test]
    fn inner_stream_is_keyed_from_the_unhashed_protected_stream_key() {
        use crate::crypt::ciphers::reference;

        // KeePass hashes the raw protected stream key inside the inner stream
        // (CryptoRandomStream): SHA-256 for Salsa20, SHA-512 for ChaCha20.
        // This module used to hash it with SHA-256 first, which only gave the
        // right Salsa20 key because the Salsa20 wrapper did not hash.
        let db = Database::new(test_config(
            OuterCipherConfig::AES256,
            InnerCipherConfig::Salsa20,
            CompressionConfig::GZip,
        ));
        let db_key = DatabaseKey::new().with_password("testing");
        let mut data = Vec::new();
        dump_kdbx3(&db, &db_key, &mut data).unwrap();

        let stream_key = parse_outer_header(&data).unwrap().protected_stream_key;

        let (_, mut decryptor, _) = decrypt_kdbx3(&data, &db_key).unwrap();
        assert_eq!(
            reference::keystream(&mut *decryptor, 64),
            reference::salsa20_keystream(&stream_key, 64)
        );

        // KeePass also accepts ChaCha20 (ID 3) as a KDBX3 inner stream and
        // keys it from SHA-512 of the raw stream key, not SHA-512(SHA-256(k)).
        // (KeePassXC 2.7 instead ignores the ID in KDBX3 and always uses
        // Salsa20.) The header is outside the outer encryption and KDBX3 has
        // no header MAC, so a written file can be switched in place.
        let range = header_entry_value_range(&data, HEADER_INNER_RANDOM_STREAM_ID);
        data[range].copy_from_slice(&3u32.to_le_bytes());

        let (config, mut decryptor, _) = decrypt_kdbx3(&data, &db_key).unwrap();
        assert_eq!(config.inner_cipher_config, InnerCipherConfig::ChaCha20);
        assert_eq!(
            reference::keystream(&mut *decryptor, 64),
            reference::chacha20_keystream(&stream_key, 64)
        );
    }

    #[test]
    fn test_rejects_argon2_kdf() {
        let mut config = test_config(
            OuterCipherConfig::AES256,
            InnerCipherConfig::Salsa20,
            CompressionConfig::GZip,
        );
        config.kdf_config = KdfConfig::Argon2 {
            iterations: 1,
            memory: 1024,
            parallelism: 1,
            version: argon2::Version::Version13,
        };

        let db = Database::new(config);
        let mut buf = Vec::new();
        assert!(matches!(
            dump_kdbx3(&db, &DatabaseKey::new().with_password("testing"), &mut buf),
            Err(DatabaseSaveError::IncompatibleWithVersion(_))
        ));
    }

    #[test]
    fn test_rejects_chacha20_outer_cipher() {
        let config = test_config(
            OuterCipherConfig::ChaCha20,
            InnerCipherConfig::Salsa20,
            CompressionConfig::GZip,
        );

        let db = Database::new(config);
        let mut buf = Vec::new();
        assert!(matches!(
            dump_kdbx3(&db, &DatabaseKey::new().with_password("testing"), &mut buf),
            Err(DatabaseSaveError::IncompatibleWithVersion(_))
        ));
    }

    #[test]
    fn test_rejects_chacha20_inner_cipher() {
        let config = test_config(
            OuterCipherConfig::AES256,
            InnerCipherConfig::ChaCha20,
            CompressionConfig::GZip,
        );

        let db = Database::new(config);
        let mut buf = Vec::new();
        assert!(matches!(
            dump_kdbx3(&db, &DatabaseKey::new().with_password("testing"), &mut buf),
            Err(DatabaseSaveError::IncompatibleWithVersion(_))
        ));
    }

    // Building the `VariantDictionary` test fixture below reuses the
    // KDBX4-only writer helpers (`VariantDictionary::new`/`set`); the
    // KDBX3-incompatibility check itself doesn't need `save_kdbx4`.
    #[cfg(feature = "save_kdbx4")]
    #[test]
    fn test_rejects_public_custom_data() {
        use crate::format::variant_dictionary::VariantDictionary;

        let mut config = test_config(
            OuterCipherConfig::AES256,
            InnerCipherConfig::Salsa20,
            CompressionConfig::GZip,
        );
        let mut public_custom_data = VariantDictionary::new();
        public_custom_data.set("example", 42);
        config.public_custom_data = Some(public_custom_data);

        let db = Database::new(config);
        let mut buf = Vec::new();
        assert!(matches!(
            dump_kdbx3(&db, &DatabaseKey::new().with_password("testing"), &mut buf),
            Err(DatabaseSaveError::IncompatibleWithVersion(_))
        ));
    }
}
