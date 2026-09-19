#[cfg(feature = "save_kdbx4")]
use byteorder::WriteBytesExt;
use byteorder::{ByteOrder, LittleEndian};
use std::collections::HashMap;
#[cfg(feature = "save_kdbx4")]
use std::io::Write;
use thiserror::Error;

#[cfg(feature = "save_kdbx4")]
use crate::format::io::WriteLengthTaggedExt;

pub const VARIANT_DICTIONARY_VERSION: u16 = 0x100;
pub const VARIANT_DICTIONARY_END: u8 = 0x0;

pub const U32_TYPE_ID: u8 = 0x04;
pub const U64_TYPE_ID: u8 = 0x05;
pub const BOOL_TYPE_ID: u8 = 0x08;
pub const I32_TYPE_ID: u8 = 0x0c;
pub const I64_TYPE_ID: u8 = 0x0d;
pub const STR_TYPE_ID: u8 = 0x18;
pub const BYTES_TYPE_ID: u8 = 0x42;

#[derive(Debug, PartialEq, Eq, Clone, Default)]
#[cfg_attr(feature = "serialization", derive(serde::Serialize))]
pub struct VariantDictionary {
    pub data: HashMap<String, VariantDictionaryValue>,
}

impl VariantDictionary {
    #[cfg(feature = "save_kdbx4")]
    pub(crate) fn new() -> Self {
        Self { data: HashMap::new() }
    }

    pub(crate) fn parse(buffer: &[u8]) -> Result<VariantDictionary, VariantDictionaryError> {
        let version = LittleEndian::read_u16(buffer.get(0..2).ok_or(VariantDictionaryError::UnexpectedEof)?);

        if version != VARIANT_DICTIONARY_VERSION {
            return Err(VariantDictionaryError::InvalidVersion { version });
        }

        let mut pos = 2;
        let mut data = HashMap::new();

        while pos + 9 < buffer.len() {
            let value_type = *buffer.get(pos).ok_or(VariantDictionaryError::UnexpectedEof)?;
            pos += 1;

            let key_length = LittleEndian::read_u32(
                buffer
                    .get(pos..(pos + 4))
                    .ok_or(VariantDictionaryError::UnexpectedEof)?,
            ) as usize;
            pos += 4;

            // Lengths are u32 values from the file; `pos + length` can
            // overflow usize on 32-bit targets, so use checked arithmetic.
            let key_end = pos
                .checked_add(key_length)
                .ok_or(VariantDictionaryError::UnexpectedEof)?;
            let key = String::from_utf8_lossy(
                buffer
                    .get(pos..key_end)
                    .ok_or(VariantDictionaryError::UnexpectedEof)?,
            )
            .to_string();
            pos = key_end;

            let value_length = LittleEndian::read_u32(
                buffer
                    .get(pos..(pos + 4))
                    .ok_or(VariantDictionaryError::UnexpectedEof)?,
            ) as usize;
            pos += 4;

            let value_end = pos
                .checked_add(value_length)
                .ok_or(VariantDictionaryError::UnexpectedEof)?;
            let value_buffer = buffer
                .get(pos..value_end)
                .ok_or(VariantDictionaryError::UnexpectedEof)?;
            pos = value_end;

            let expected_len = match value_type {
                U32_TYPE_ID | I32_TYPE_ID => Some(4),
                U64_TYPE_ID | I64_TYPE_ID => Some(8),
                BOOL_TYPE_ID => Some(1),
                STR_TYPE_ID | BYTES_TYPE_ID => None,
                _ => {
                    return Err(VariantDictionaryError::InvalidValueType { value_type });
                }
            };

            if let Some(expected_len) = expected_len {
                if value_buffer.len() != expected_len {
                    return Err(VariantDictionaryError::InvalidValueLength {
                        value_type,
                        expected_len,
                        actual_len: value_buffer.len(),
                    });
                }
            }

            let value = match value_type {
                U32_TYPE_ID => VariantDictionaryValue::UInt32(LittleEndian::read_u32(value_buffer)),
                U64_TYPE_ID => VariantDictionaryValue::UInt64(LittleEndian::read_u64(value_buffer)),
                BOOL_TYPE_ID => VariantDictionaryValue::Bool(value_buffer != [0]),
                I32_TYPE_ID => VariantDictionaryValue::Int32(LittleEndian::read_i32(value_buffer)),
                I64_TYPE_ID => VariantDictionaryValue::Int64(LittleEndian::read_i64(value_buffer)),
                STR_TYPE_ID => {
                    VariantDictionaryValue::String(String::from_utf8_lossy(value_buffer).to_string())
                }
                BYTES_TYPE_ID => VariantDictionaryValue::ByteArray(value_buffer.to_vec()),
                _ => unreachable!("value_type already validated above"),
            };

            data.insert(key, value);
        }

        match buffer.get(pos) {
            Some(&b) if b == VARIANT_DICTIONARY_END => {}
            // even though we can determine when to stop parsing a VariantDictionary by where we
            // are in the buffer, there should always be a value_type = 0 entry to denote that a
            // VariantDictionary is finished
            _ => return Err(VariantDictionaryError::NotTerminated),
        }

        Ok(VariantDictionary { data })
    }

    #[cfg(feature = "save_kdbx4")]
    pub(crate) fn dump(&self, writer: &mut dyn Write) -> Result<(), std::io::Error> {
        writer.write_u16::<LittleEndian>(VARIANT_DICTIONARY_VERSION)?;

        for (field_name, field_value) in &self.data {
            match field_value {
                VariantDictionaryValue::UInt32(value) => {
                    writer.write_u8(U32_TYPE_ID)?;
                    writer.write_with_len(field_name.as_bytes())?;
                    writer.write_u32::<LittleEndian>(4)?;
                    writer.write_u32::<LittleEndian>(*value)?;
                }
                VariantDictionaryValue::UInt64(value) => {
                    writer.write_u8(U64_TYPE_ID)?;
                    writer.write_with_len(field_name.as_bytes())?;
                    writer.write_u32::<LittleEndian>(8)?;
                    writer.write_u64::<LittleEndian>(*value)?;
                }
                VariantDictionaryValue::Bool(value) => {
                    writer.write_u8(BOOL_TYPE_ID)?;
                    writer.write_with_len(field_name.as_bytes())?;
                    writer.write_u32::<LittleEndian>(1)?;
                    writer.write_u8(if *value { 1 } else { 0 })?;
                }
                VariantDictionaryValue::Int32(value) => {
                    writer.write_u8(I32_TYPE_ID)?;
                    writer.write_with_len(field_name.as_bytes())?;
                    writer.write_u32::<LittleEndian>(4)?;
                    writer.write_i32::<LittleEndian>(*value)?;
                }
                VariantDictionaryValue::Int64(value) => {
                    writer.write_u8(I64_TYPE_ID)?;
                    writer.write_with_len(field_name.as_bytes())?;
                    writer.write_u32::<LittleEndian>(8)?;
                    writer.write_i64::<LittleEndian>(*value)?;
                }
                VariantDictionaryValue::String(value) => {
                    writer.write_u8(STR_TYPE_ID)?;
                    writer.write_with_len(field_name.as_bytes())?;
                    writer.write_with_len(value.as_bytes())?;
                }
                VariantDictionaryValue::ByteArray(value) => {
                    writer.write_u8(BYTES_TYPE_ID)?;
                    writer.write_with_len(field_name.as_bytes())?;
                    writer.write_with_len(value)?;
                }
            };
        }

        // signify end of variant dictionary
        writer.write_u8(VARIANT_DICTIONARY_END)?;
        Ok(())
    }

    pub(crate) fn get<'a, T: 'a>(&'a self, key: &str) -> Result<&'a T, VariantDictionaryError>
    where
        &'a VariantDictionaryValue: Into<Option<&'a T>>,
    {
        let vdv = self
            .data
            .get(key)
            .ok_or_else(|| VariantDictionaryError::MissingKey { key: key.to_owned() })?;

        vdv.into()
            .ok_or_else(|| VariantDictionaryError::Mistyped { key: key.to_owned() })
    }

    #[cfg(feature = "save_kdbx4")]
    pub(crate) fn set<T>(&mut self, key: &str, value: T)
    where
        T: Into<VariantDictionaryValue>,
    {
        self.data.insert(key.to_string(), value.into());
    }
}

#[derive(Debug, PartialEq, Eq, Clone)]
#[cfg_attr(feature = "serialization", derive(serde::Serialize))]
pub enum VariantDictionaryValue {
    UInt32(u32),
    UInt64(u64),
    Bool(bool),
    Int32(i32),
    Int64(i64),
    String(String),
    ByteArray(Vec<u8>),
}

impl From<u32> for VariantDictionaryValue {
    fn from(v: u32) -> Self {
        VariantDictionaryValue::UInt32(v)
    }
}

impl From<u64> for VariantDictionaryValue {
    fn from(v: u64) -> Self {
        VariantDictionaryValue::UInt64(v)
    }
}

impl From<i32> for VariantDictionaryValue {
    fn from(v: i32) -> Self {
        VariantDictionaryValue::Int32(v)
    }
}

impl From<i64> for VariantDictionaryValue {
    fn from(v: i64) -> Self {
        VariantDictionaryValue::Int64(v)
    }
}

impl From<bool> for VariantDictionaryValue {
    fn from(v: bool) -> Self {
        VariantDictionaryValue::Bool(v)
    }
}

impl From<String> for VariantDictionaryValue {
    fn from(v: String) -> Self {
        VariantDictionaryValue::String(v)
    }
}

impl From<Vec<u8>> for VariantDictionaryValue {
    fn from(v: Vec<u8>) -> Self {
        VariantDictionaryValue::ByteArray(v)
    }
}

impl<'a> From<&'a VariantDictionaryValue> for Option<&'a u32> {
    fn from(val: &'a VariantDictionaryValue) -> Self {
        match val {
            VariantDictionaryValue::UInt32(v) => Some(v),
            _ => None,
        }
    }
}

impl<'a> From<&'a VariantDictionaryValue> for Option<&'a u64> {
    fn from(val: &'a VariantDictionaryValue) -> Self {
        match val {
            VariantDictionaryValue::UInt64(v) => Some(v),
            _ => None,
        }
    }
}

impl<'a> From<&'a VariantDictionaryValue> for Option<&'a bool> {
    fn from(val: &'a VariantDictionaryValue) -> Self {
        match val {
            VariantDictionaryValue::Bool(v) => Some(v),
            _ => None,
        }
    }
}

impl<'a> From<&'a VariantDictionaryValue> for Option<&'a i32> {
    fn from(val: &'a VariantDictionaryValue) -> Self {
        match val {
            VariantDictionaryValue::Int32(v) => Some(v),
            _ => None,
        }
    }
}

impl<'a> From<&'a VariantDictionaryValue> for Option<&'a i64> {
    fn from(val: &'a VariantDictionaryValue) -> Self {
        match val {
            VariantDictionaryValue::Int64(v) => Some(v),
            _ => None,
        }
    }
}

impl<'a> From<&'a VariantDictionaryValue> for Option<&'a String> {
    fn from(val: &'a VariantDictionaryValue) -> Self {
        match val {
            VariantDictionaryValue::String(v) => Some(v),
            _ => None,
        }
    }
}

impl<'a> From<&'a VariantDictionaryValue> for Option<&'a Vec<u8>> {
    fn from(val: &'a VariantDictionaryValue) -> Self {
        match val {
            VariantDictionaryValue::ByteArray(v) => Some(v),
            _ => None,
        }
    }
}

/// Errors while parsing a VariantDictionary
#[derive(Debug, Error)]
pub enum VariantDictionaryError {
    #[error("Invalid variant dictionary version: {}", version)]
    InvalidVersion { version: u16 },

    #[error("Invalid value type: {}", value_type)]
    InvalidValueType { value_type: u8 },

    #[error(
        "Invalid value length for type {}: expected {} bytes, got {}",
        value_type,
        expected_len,
        actual_len
    )]
    InvalidValueLength {
        value_type: u8,
        expected_len: usize,
        actual_len: usize,
    },

    #[error("Missing key: {}", key)]
    MissingKey { key: String },

    #[error("Mistyped value: {}", key)]
    Mistyped { key: String },

    #[error("VariantDictionary did not end with null byte, when it should")]
    NotTerminated,

    #[error("Unexpected end of buffer while parsing VariantDictionary")]
    UnexpectedEof,
}

#[cfg(test)]
mod variant_dictionary_tests {
    use hex_literal::hex;

    use super::*;

    #[test]
    fn parse_does_not_panic_on_empty_buffer() {
        let res = VariantDictionary::parse(&[]);
        assert!(matches!(res, Err(VariantDictionaryError::UnexpectedEof)));
    }

    #[test]
    fn parse_does_not_panic_on_huge_key_length() {
        // ver t key_len (huge, near u32::MAX), padded so the loop guard is entered
        let res = VariantDictionary::parse(&hex!("000104F0FFFFFF0000000000"));
        assert!(matches!(res, Err(VariantDictionaryError::UnexpectedEof)));
    }

    #[test]
    fn parse_does_not_panic_on_huge_value_length() {
        // ver t key_len key val_len (huge, near u32::MAX)
        let res = VariantDictionary::parse(&hex!("000104030000004142430500000010"));
        assert!(matches!(res, Err(VariantDictionaryError::UnexpectedEof)));
    }

    #[test]
    fn parse_errors_on_undersized_typed_value() {
        // ver t key_len key val_len(=1) value(1 byte, too short for a U32)
        let res = VariantDictionary::parse(&hex!("00010403000000414243010000000000"));
        assert!(matches!(
            res,
            Err(VariantDictionaryError::InvalidValueLength {
                value_type: U32_TYPE_ID,
                expected_len: 4,
                actual_len: 1,
            })
        ));
    }

    #[test]
    fn parsing_errors() -> Result<(), VariantDictionaryError> {
        let res = VariantDictionary::parse("not-a-variant-dictionary".as_bytes());
        assert!(matches!(res, Err(VariantDictionaryError::InvalidVersion { .. })));

        let res = VariantDictionary::parse(&hex!("0001"));
        assert!(matches!(res, Err(VariantDictionaryError::NotTerminated)));

        let res = VariantDictionary::parse(&hex!("000100"));
        assert!(res.is_ok());

        // ver t key_len key val_len value termination
        // | | | | | | |
        let res = VariantDictionary::parse(&hex!("000104030000004142430400000015CD5B0700"))?;
        assert_eq!(res.get::<u32>("ABC")?, &123456789);

        // ver t key_len key val_len termination
        // | | | | | |
        let res = VariantDictionary::parse(&hex!("0001AA0200000041420000000000"));
        dbg!(&res);
        assert!(matches!(
            res,
            Err(VariantDictionaryError::InvalidValueType { value_type: 0xAA })
        ));

        Ok(())
    }

    #[test]
    #[cfg(feature = "save_kdbx4")]
    fn variant_dictionary() {
        let mut vd = VariantDictionary::new();

        vd.set("a-u32", 42u32);
        vd.set("a-u64", 1337u64);
        vd.set("a-i32", -2i32);
        vd.set("a-i64", -31337i64);
        vd.set("a-bool", true);
        vd.set("a-string", "Testing".to_string());
        vd.set("a-bytes", "testing".as_bytes().to_vec());

        assert!(vd.get::<bool>("key-not-exist").is_err());

        assert!(vd.get::<u32>("a-string").is_err());
        assert!(vd.get::<u64>("a-string").is_err());
        assert!(vd.get::<i32>("a-string").is_err());
        assert!(vd.get::<i64>("a-string").is_err());
        assert!(vd.get::<bool>("a-string").is_err());
        assert!(vd.get::<String>("a-bytes").is_err());
        assert!(vd.get::<Vec<u8>>("a-string").is_err());

        assert_eq!(vd.get::<u32>("a-u32").unwrap(), &42u32);
        assert_eq!(vd.get::<u64>("a-u64").unwrap(), &1337u64);
        assert_eq!(vd.get::<i32>("a-i32").unwrap(), &-2i32);
        assert_eq!(vd.get::<i64>("a-i64").unwrap(), &-31337i64);
        assert_eq!(vd.get::<bool>("a-bool").unwrap(), &true);
        assert_eq!(vd.get::<String>("a-string").unwrap(), "Testing");
        assert_eq!(vd.get::<Vec<u8>>("a-bytes").unwrap(), "testing".as_bytes());

        let mut vd_data = Vec::new();
        vd.dump(&mut vd_data).unwrap();

        let vd_parsed = VariantDictionary::parse(&vd_data).unwrap();
        assert_eq!(vd_parsed, vd);
    }
}
