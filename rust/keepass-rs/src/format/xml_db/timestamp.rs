use base64::{engine::general_purpose as base64_engine, Engine as _};
use chrono::NaiveDateTime;
use serde::{Deserialize, Serialize, Serializer};
use std::convert::TryInto;

/// In KDBX4, timestamps are stored as seconds, Base64 encoded, since 0001-01-01 00:00:00.
/// This function returns the epoch baseline used by KDBX for date serialization.
pub fn get_epoch_baseline() -> chrono::NaiveDateTime {
    #[allow(clippy::unwrap_used)] // This is a known constant, so unwrap is safe here.
    chrono::NaiveDateTime::parse_from_str("0001-01-01T00:00:00", "%Y-%m-%dT%H:%M:%S").unwrap()
}

#[derive(Debug, Clone, Copy)]
pub enum TimestampMode {
    Base64,
    Iso8601,
}

#[derive(Debug)]
pub struct Timestamp {
    pub mode: TimestampMode,
    pub time: NaiveDateTime,
}

impl Timestamp {
    pub fn new_base64(time: NaiveDateTime) -> Self {
        Timestamp {
            mode: TimestampMode::Base64,
            time,
        }
    }

    pub fn new_iso8601(time: NaiveDateTime) -> Self {
        Timestamp {
            mode: TimestampMode::Iso8601,
            time,
        }
    }
}

impl From<Timestamp> for NaiveDateTime {
    fn from(t: Timestamp) -> Self {
        t.time
    }
}

impl From<NaiveDateTime> for Timestamp {
    fn from(t: NaiveDateTime) -> Self {
        // Default to Base64 for KDBX 4.x (the only format ManyKee targets).
        // The original format is preserved when timestamps are deserialized from XML,
        // because Deserialize already sets the correct mode.
        Timestamp::new_base64(t)
    }
}

impl<'de> Deserialize<'de> for Timestamp {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let t = String::deserialize(deserializer)?;

        match chrono::NaiveDateTime::parse_from_str(&t, "%Y-%m-%dT%H:%M:%SZ") {
            Ok(ndt) => Ok(Timestamp::new_iso8601(ndt)),

            // If we don't have a valid ISO 8601 string, assume we have found a Base64 encoded int.
            _ => {
                let v = base64_engine::STANDARD
                    .decode(t)
                    .map_err(serde::de::Error::custom)?;

                // A KDBX4 Base64 timestamp is an 8-byte little-endian i64 of
                // seconds since the epoch baseline. Reject anything else
                // instead of panicking (too short) or silently truncating
                // (too long) on a crafted/corrupted file.
                let a: [u8; 8] = v.as_slice().try_into().map_err(|_| {
                    serde::de::Error::custom(format!(
                        "invalid Base64 timestamp: expected 8 bytes, got {}",
                        v.len()
                    ))
                })?;
                // `Duration::seconds` and `NaiveDateTime + Duration` both
                // panic when the value is out of range, so do the arithmetic
                // with the checked variants and report a parse error instead.
                let seconds = i64::from_le_bytes(a);
                let ndt = chrono::TimeDelta::try_seconds(seconds)
                    .and_then(|delta| get_epoch_baseline().checked_add_signed(delta))
                    .ok_or_else(|| {
                        serde::de::Error::custom(format!(
                            "Base64 timestamp out of range: {} seconds since 0001-01-01",
                            seconds
                        ))
                    })?;

                Ok(Timestamp::new_base64(ndt))
            }
        }
    }
}

impl Serialize for Timestamp {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match self.mode {
            TimestampMode::Iso8601 => {
                let s = self.time.format("%Y-%m-%dT%H:%M:%SZ").to_string();
                serializer.serialize_str(&s)
            }
            TimestampMode::Base64 => {
                let duration = self.time - get_epoch_baseline();
                let seconds = duration.num_seconds();
                let b = seconds.to_le_bytes();
                let b64 = base64_engine::STANDARD.encode(b);
                serializer.serialize_str(&b64)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Serialize, Deserialize)]
    struct Test<T>(T);

    #[test]
    fn test_deserialize_timestamp_iso8601() {
        let ts_str = "2023-10-05T12:34:56Z";
        let ts: Timestamp = quick_xml::de::from_str(&format!("{}", ts_str)).unwrap();
        assert_eq!(
            ts.time,
            NaiveDateTime::parse_from_str("2023-10-05T12:34:56", "%Y-%m-%dT%H:%M:%S").unwrap()
        );
        match ts.mode {
            TimestampMode::Iso8601 => (),
            _ => panic!("Expected Iso8601 mode"),
        }
    }

    #[test]
    fn test_deserialize_timestamp_base64() {
        let ts_str = "AQAAAAAAAAA="; // Base64 for 1 second since epoch
        let ts: Timestamp = quick_xml::de::from_str(&format!("{}", ts_str)).unwrap();
        assert_eq!(ts.time, get_epoch_baseline() + chrono::Duration::seconds(1));
        match ts.mode {
            TimestampMode::Base64 => (),
            _ => panic!("Expected Base64 mode"),
        }
    }

    #[test]
    fn test_serialize_timestamp_iso8601() {
        let ts = Timestamp {
            mode: TimestampMode::Iso8601,
            time: NaiveDateTime::parse_from_str("2023-10-05T12:34:56", "%Y-%m-%dT%H:%M:%S").unwrap(),
        };
        let serialized = quick_xml::se::to_string(&Test(ts)).unwrap();
        assert_eq!(serialized, "<Test>2023-10-05T12:34:56Z</Test>");
    }

    #[test]
    fn test_base64_timestamp_roundtrip() {
        // Create a Base64 timestamp, serialize, deserialize, verify mode and time preserved
        let dt = NaiveDateTime::parse_from_str("2024-06-15T10:30:00", "%Y-%m-%dT%H:%M:%S").unwrap();
        let ts = Timestamp::new_base64(dt);

        // Serialize to XML string
        let serialized = quick_xml::se::to_string(&Test(ts)).unwrap();
        // Should be Base64 encoded, not ISO 8601 (no dashes/colons in the value)
        assert!(
            !serialized.contains("2024-06-15"),
            "Expected Base64 encoding, got ISO 8601: {}",
            serialized
        );

        // Deserialize back
        let deserialized: Test<Timestamp> = quick_xml::de::from_str(&serialized).unwrap();
        match deserialized.0.mode {
            TimestampMode::Base64 => (),
            _ => panic!("Expected Base64 mode after round-trip"),
        }
        assert_eq!(deserialized.0.time, dt);
    }

    #[test]
    fn test_from_naivedatetime_uses_base64() {
        let dt = NaiveDateTime::parse_from_str("2024-01-01T00:00:00", "%Y-%m-%dT%H:%M:%S").unwrap();
        let ts: Timestamp = dt.into();
        match ts.mode {
            TimestampMode::Base64 => (),
            _ => panic!("From<NaiveDateTime> should default to Base64 mode"),
        }
    }

    #[test]
    fn test_deserialize_timestamp_base64_too_short_errors() {
        // 4 bytes decoded, not 8 - must error, not panic.
        let ts_str = base64_engine::STANDARD.encode([1, 2, 3, 4]);
        let result: Result<Timestamp, _> = quick_xml::de::from_str(&format!("{}", ts_str));
        assert!(result.is_err());
    }

    #[test]
    fn test_deserialize_timestamp_base64_too_long_errors() {
        // 12 bytes decoded, not 8 - must error instead of silently truncating.
        let ts_str = base64_engine::STANDARD.encode([1u8; 12]);
        let result: Result<Timestamp, _> = quick_xml::de::from_str(&format!("{}", ts_str));
        assert!(result.is_err());
    }

    #[test]
    fn test_deserialize_timestamp_base64_out_of_range_errors() {
        // i64::MAX / i64::MIN seconds do not fit in a chrono TimeDelta, and a
        // value that does fit can still overflow NaiveDateTime. All of these
        // must be reported as errors instead of panicking.
        for seconds in [i64::MAX, i64::MIN, i64::MAX / 1_000, i64::MIN / 1_000] {
            let ts_str = base64_engine::STANDARD.encode(seconds.to_le_bytes());
            let result: Result<Timestamp, _> = quick_xml::de::from_str(&format!("{}", ts_str));
            assert!(result.is_err(), "{} seconds must not deserialize", seconds);
        }
    }

    #[test]
    fn test_serialize_timestamp_base64() {
        let ts = Timestamp {
            mode: TimestampMode::Base64,
            time: get_epoch_baseline() + chrono::Duration::seconds(1),
        };

        let serialized = quick_xml::se::to_string(&Test(ts)).unwrap();
        assert_eq!(serialized, "<Test>AQAAAAAAAAA=</Test>");
    }
}
