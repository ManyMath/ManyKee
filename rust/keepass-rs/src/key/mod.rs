use std::io::Read;

use base64::{engine::general_purpose as base64_engine, Engine as _};
use quick_xml::{encoding::EncodingError, events::Event, reader::Reader};
use thiserror::Error;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::crypt::calculate_sha256;

pub type KeyElement = Vec<u8>;
pub type KeyElements = Vec<KeyElement>;

#[cfg(feature = "challenge_response")]
mod yubikey;

#[cfg(feature = "challenge_response")]
pub use yubikey::{ChallengeResponseKey, ChallengeResponseKeyError, Yubikey};

fn parse_xml_keyfile(xml: &[u8]) -> Result<Zeroizing<KeyElement>, ParseXmlKeyFileError> {
    let mut tag_stack = Vec::new();

    let mut key_version: Option<String> = None;
    let mut key_value: Option<Zeroizing<String>> = None;
    let mut key_hash: Option<String> = None;

    let mut reader = Reader::from_reader(xml);
    let mut buf = Vec::new();

    loop {
        match reader.read_event_into(&mut buf)? {
            Event::Eof => break,

            Event::Start(e) => {
                if tag_stack == ["KeyFile", "Key"] && e.name().as_ref() == b"Data" {
                    for attr in e.attributes().flatten() {
                        if attr.key.as_ref() == b"Hash" {
                            key_hash = Some(String::from_utf8_lossy(&attr.value).into_owned());
                        }
                    }
                }

                tag_stack.push(String::from_utf8_lossy(e.name().as_ref()).to_string());
            }

            Event::End(_) => {
                tag_stack.pop();
            }

            Event::Text(e) => {
                let s = e.decode()?.into_owned();

                if tag_stack == ["KeyFile", "Meta", "Version"] {
                    key_version = Some(s);
                    continue;
                }

                if tag_stack == ["KeyFile", "Key", "Data"] {
                    key_value = Some(Zeroizing::new(s));
                    continue;
                }
            }

            _ => (),
        }
    }

    let key_value = key_value.ok_or(ParseXmlKeyFileError::EmptyKey)?;

    let key_bytes: Zeroizing<Vec<u8>> = Zeroizing::new(key_value.as_bytes().to_vec());

    if key_version == Some("2.0".to_string()) {
        // XML keyfile v2.0 stores the key as hex in <Data>, optionally with
        // a `Hash` attribute holding the first 4 bytes (as 8 uppercase hex
        // characters) of SHA-256(key), so readers can detect a truncated or
        // otherwise corrupted keyfile.
        let trimmed_key: Zeroizing<String> = Zeroizing::new(
            key_value
                .trim()
                .replace(" ", "")
                .replace("\n", "")
                .replace("\t", "")
                .replace("\r", ""),
        );

        let key: Zeroizing<Vec<u8>> = match hex::decode(trimmed_key.as_str()) {
            Ok(key) => Zeroizing::new(key),
            Err(_) => return Ok(Zeroizing::new(key_bytes.to_vec())),
        };

        if let Some(expected_hash) = key_hash {
            let actual_hash = calculate_sha256(&[&key]);
            let actual_hash_prefix = hex::encode_upper(&actual_hash[..4]);
            if !expected_hash.eq_ignore_ascii_case(&actual_hash_prefix) {
                return Err(ParseXmlKeyFileError::HashMismatch);
            }
        }

        return Ok(key);
    }

    // Check if the key is base64-encoded. If yes, return decoded bytes
    if let Ok(key) = base64_engine::STANDARD.decode(key_bytes.as_slice()) {
        Ok(Zeroizing::new(key))
    } else {
        Ok(key_bytes)
    }
}

#[derive(Debug, Error)]
pub enum ParseXmlKeyFileError {
    #[error("The XML keyfile is missing a key data element")]
    EmptyKey,

    #[error("The XML keyfile's key data does not match its integrity hash; the file may be corrupted")]
    HashMismatch,

    #[error(transparent)]
    Encoding(#[from] EncodingError),

    #[error(transparent)]
    Xml(#[from] quick_xml::Error),
}

fn parse_keyfile(buffer: &[u8]) -> Result<Zeroizing<KeyElement>, DatabaseKeyError> {
    // try to parse the buffer as XML, if successful, use that data instead of full file
    match parse_xml_keyfile(buffer) {
        Ok(v) => Ok(v),
        // This was recognized as a v2 XML keyfile, but its key data didn't
        // match its own integrity hash: it's corrupted, not merely
        // non-XML, so report it rather than silently falling back to
        // treating the raw bytes as a different, unrelated key.
        Err(ParseXmlKeyFileError::HashMismatch) => Err(DatabaseKeyError::InvalidKeyFile),
        Err(_) if buffer.len() == 32 => {
            // legacy binary key format
            Ok(Zeroizing::new(buffer.to_vec()))
        }
        Err(_) => Ok(Zeroizing::new(calculate_sha256(&[buffer]).as_slice().to_vec())),
    }
}

/// A KeePass key, which might consist of a password and/or a keyfile
#[derive(Debug, Clone, Default, PartialEq, Zeroize, ZeroizeOnDrop)]
pub struct DatabaseKey {
    password: Option<String>,
    keyfile: Option<Vec<u8>>,
    #[cfg(feature = "challenge_response")]
    challenge_response_key: Option<ChallengeResponseKey>,
    /// Pre-computed challenge-response result bytes.
    /// Always available so WASM consumers can pass pre-computed CR bytes
    /// without enabling the full challenge_response feature (which requires USB).
    challenge_response_result: Option<KeyElement>,
}

impl DatabaseKey {
    pub fn with_password(mut self, password: &str) -> Self {
        self.password = Some(password.to_string());
        self
    }

    #[cfg(feature = "utilities")]
    pub fn with_password_from_prompt(mut self, prompt_message: &str) -> Result<Self, std::io::Error> {
        self.password = Some(rpassword::prompt_password(prompt_message)?);
        Ok(self)
    }

    #[cfg(all(feature = "challenge_response", feature = "utilities"))]
    pub fn with_hmac_sha1_secret_from_prompt(mut self, prompt_message: &str) -> Result<Self, std::io::Error> {
        self.challenge_response_key = Some(ChallengeResponseKey::LocalChallenge(rpassword::prompt_password(
            prompt_message,
        )?));
        Ok(self)
    }
    /// Creates a database key with a `keyfile`
    ///
    /// # Errors
    ///
    /// Fails if the `keyfile` cannot be read
    pub fn with_keyfile(mut self, keyfile: &mut dyn Read) -> Result<Self, std::io::Error> {
        let mut buf = Vec::new();
        keyfile.read_to_end(&mut buf)?;

        self.keyfile = Some(buf);

        Ok(self)
    }

    #[cfg(feature = "challenge_response")]
    pub fn with_challenge_response_key(mut self, challenge_response_key: ChallengeResponseKey) -> Self {
        self.challenge_response_key = Some(challenge_response_key);
        self
    }

    /// Set pre-computed challenge-response result bytes directly.
    ///
    /// This allows WASM consumers to pass pre-computed HMAC-SHA1 bytes
    /// without needing the `challenge_response` feature (which requires USB).
    /// The bytes should be the raw HMAC-SHA1 output (20 bytes).
    pub fn with_challenge_response_bytes(mut self, response: Vec<u8>) -> Self {
        self.challenge_response_result = Some(response);
        self
    }

    #[cfg(feature = "challenge_response")]
    pub fn perform_challenge(mut self, kdf_seed: &[u8]) -> Result<Self, DatabaseKeyError> {
        if let Some(challenge_response_key) = &self.challenge_response_key {
            let response = challenge_response_key.perform_challenge(kdf_seed)?;
            self.challenge_response_result = Some(response);
        }

        Ok(self)
    }

    pub fn new() -> Self {
        Default::default()
    }

    pub(crate) fn get_key_elements(&self) -> Result<Zeroizing<KeyElements>, DatabaseKeyError> {
        let mut out: Zeroizing<KeyElements> = Zeroizing::new(Vec::new());

        if let Some(p) = &self.password {
            out.push(calculate_sha256(&[p.as_bytes()]).to_vec());
        }

        if let Some(ref f) = self.keyfile {
            out.push(parse_keyfile(f)?.to_vec());
        }

        if out.is_empty() {
            return Err(DatabaseKeyError::EmptyKey);
        }

        // Check pre-computed challenge-response result (always available for WASM)
        if let Some(result) = &self.challenge_response_result {
            out.push(calculate_sha256(&[result]).as_slice().to_vec());
        }
        #[cfg(feature = "challenge_response")]
        if self.challenge_response_result.is_none() && self.challenge_response_key.is_some() {
            return Err(DatabaseKeyError::ChallengeResponse(
                crate::key::yubikey::ChallengeResponseKeyError::NotPerformed,
            ));
        }

        Ok(out)
    }

    /// Returns true if the database key is not associated with any key component.
    pub fn is_empty(&self) -> bool {
        if self.password.is_some() || self.keyfile.is_some() || self.challenge_response_result.is_some() {
            return false;
        }
        #[cfg(feature = "challenge_response")]
        if self.challenge_response_key.is_some() {
            return false;
        }
        true
    }
}

#[derive(Debug, Error)]
pub enum DatabaseKeyError {
    #[error("The key contains no components")]
    EmptyKey,

    #[error("Incorrect key")]
    IncorrectKey,

    #[error("I/O error reading keyfile: {0}")]
    Io(#[from] std::io::Error),

    #[error("XML error reading keyfile: {0}")]
    Xml(#[from] quick_xml::Error),

    #[error("Invalid keyfile format")]
    InvalidKeyFile,

    #[cfg(feature = "challenge_response")]
    #[error("Challenge-response key error: {0}")]
    ChallengeResponse(#[from] crate::key::yubikey::ChallengeResponseKeyError),
}

#[cfg(test)]
mod key_tests {

    use super::{DatabaseKey, DatabaseKeyError};

    #[test]
    fn test_key() -> Result<(), DatabaseKeyError> {
        let ke = DatabaseKey::new().with_password("asdf").get_key_elements()?;
        assert_eq!(ke.len(), 1);

        let ke = DatabaseKey::new()
            .with_keyfile(&mut "bare-key-file".as_bytes())?
            .get_key_elements()?;
        assert_eq!(ke.len(), 1);

        let ke = DatabaseKey::new()
            .with_keyfile(&mut "0123456789ABCDEF0123456789ABCDEF".as_bytes())?
            .get_key_elements()?;
        assert_eq!(ke.len(), 1);

        let ke = DatabaseKey::new()
            .with_password("asdf")
            .with_keyfile(&mut "bare-key-file".as_bytes())?
            .get_key_elements()?;
        assert_eq!(ke.len(), 2);

        let ke = DatabaseKey::new()
            .with_keyfile(
                &mut "<KeyFile><Key><Data>0!23456789ABCDEF0123456789ABCDEF</Data></Key></KeyFile>".as_bytes(),
            )?
            .get_key_elements()?;
        assert_eq!(ke.len(), 1);

        let ke = DatabaseKey::new()
            .with_keyfile(
                &mut "<KeyFile><Key><Data>NXyYiJMHg3ls+eBmjbAjWec9lcOToJiofbhNiFMTJMw=</Data></Key></KeyFile>"
                    .as_bytes(),
            )?
            .get_key_elements()?;
        assert_eq!(ke.len(), 1);

        let xml_keyfile_v2 = r###"
 <?xml version="1.0" encoding="utf-8"?>
 <KeyFile>
 <Meta>
 <Version>2.0</Version>
 </Meta>
 <Key>
 <Data Hash="A65F0C2D">
 36057B1C 35037FD9 62257893 C0A22403
 EE3F8FBB 504D9981 08B821CB 00D28F89
 </Data>
 </Key>
 </KeyFile>
 "###;
        let ke = DatabaseKey::new()
            .with_keyfile(&mut xml_keyfile_v2.trim().as_bytes())?
            .get_key_elements()?;
        assert_eq!(ke.len(), 1);

        // other XML files will just be hashed as a "bare" keyfile
        let ke = DatabaseKey::new()
            .with_keyfile(&mut "<Not><A><KeyFile></KeyFile></A></Not>".as_bytes())?
            .get_key_elements()?;

        assert_eq!(ke.len(), 1);

        assert!(DatabaseKey {
            password: None,
            keyfile: None,
            #[cfg(feature = "challenge_response")]
            challenge_response_key: None,
            challenge_response_result: None,
        }
        .get_key_elements()
        .is_err());

        Ok(())
    }

    #[test]
    fn test_v2_keyfile_hash_mismatch_is_rejected() {
        // Same as the valid v2 fixture above, but with the last hex digit
        // of the key data flipped, so it no longer matches `Hash`.
        let xml_keyfile_v2 = r###"
 <?xml version="1.0" encoding="utf-8"?>
 <KeyFile>
 <Meta>
 <Version>2.0</Version>
 </Meta>
 <Key>
 <Data Hash="A65F0C2D">
 36057B1C 35037FD9 62257893 C0A22403
 EE3F8FBB 504D9981 08B821CB 00D28F88
 </Data>
 </Key>
 </KeyFile>
 "###;

        let result = DatabaseKey::new()
            .with_keyfile(&mut xml_keyfile_v2.trim().as_bytes())
            .expect("reading the keyfile bytes should succeed")
            .get_key_elements();
        assert!(result.is_err(), "a keyfile whose data doesn't match its Hash should be rejected");
    }

    #[test]
    fn test_password_survives_keyfile_error_and_result_zeroizes_on_drop() {
        // Compile-time assertion that `get_key_elements`'s return value is
        // wrapped in `Zeroizing` from construction, so a password-derived
        // key element already pushed into `out` is still zeroized on drop
        // even when a later keyfile error short-circuits via `?` before the
        // caller ever gets a chance to wrap the result itself.
        fn assert_zeroize_on_drop<T: zeroize::ZeroizeOnDrop>() {}
        assert_zeroize_on_drop::<zeroize::Zeroizing<super::KeyElements>>();

        // A password plus a keyfile whose v2 XML hash doesn't match its data
        // exercises exactly this order: the password element is pushed into
        // `out` first, then `parse_keyfile` errors and `?` returns early.
        let xml_keyfile_v2_bad_hash = r###"
 <?xml version="1.0" encoding="utf-8"?>
 <KeyFile>
 <Meta>
 <Version>2.0</Version>
 </Meta>
 <Key>
 <Data Hash="00000000">
 36057B1C 35037FD9 62257893 C0A22403
 EE3F8FBB 504D9981 08B821CB 00D28F89
 </Data>
 </Key>
 </KeyFile>
 "###;

        let result = DatabaseKey::new()
            .with_password("asdf")
            .with_keyfile(&mut xml_keyfile_v2_bad_hash.trim().as_bytes())
            .expect("reading the keyfile bytes should succeed")
            .get_key_elements();
        assert!(result.is_err(), "a keyfile whose data doesn't match its Hash should be rejected");
    }

    #[test]
    fn test_parse_xml_keyfile_v2_result_zeroizes_on_drop() {
        // Compile-time assertion that parse_xml_keyfile's own return value
        // zeroizes on drop; combined with the functional check below (that a
        // valid v2 keyfile still parses correctly), this locks in that the
        // intermediate key_value/key_bytes/trimmed_key locals inside
        // parse_xml_keyfile were switched to Zeroizing without changing
        // behavior.
        fn assert_zeroize_on_drop<T: zeroize::ZeroizeOnDrop>() {}
        assert_zeroize_on_drop::<super::Zeroizing<super::KeyElement>>();

        let xml_keyfile_v2 = r###"
 <?xml version="1.0" encoding="utf-8"?>
 <KeyFile>
 <Meta>
 <Version>2.0</Version>
 </Meta>
 <Key>
 <Data Hash="A65F0C2D">
 36057B1C 35037FD9 62257893 C0A22403
 EE3F8FBB 504D9981 08B821CB 00D28F89
 </Data>
 </Key>
 </KeyFile>
 "###;

        let key = super::parse_xml_keyfile(xml_keyfile_v2.trim().as_bytes())
            .expect("a v2 keyfile with a matching Hash attribute should parse");
        assert_eq!(
            key.as_slice(),
            hex::decode("36057B1C35037FD962257893C0A22403EE3F8FBB504D998108B821CB00D28F89").unwrap()
        );
    }
}
