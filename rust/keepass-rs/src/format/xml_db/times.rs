use serde::{Deserialize, Serialize};

use crate::format::xml_db::{
    custom_serde::{cs_opt_bool, cs_opt_fromstr, cs_opt_string},
    timestamp::{Timestamp, TimestampMode},
};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct Times {
    #[serde(default, with = "cs_opt_string")]
    pub creation_time: Option<Timestamp>,
    #[serde(default, with = "cs_opt_string")]
    pub last_modification_time: Option<Timestamp>,
    #[serde(default, with = "cs_opt_string")]
    pub last_access_time: Option<Timestamp>,
    #[serde(default, with = "cs_opt_string")]
    pub expiry_time: Option<Timestamp>,

    #[serde(default, with = "cs_opt_bool", skip_serializing_if = "Option::is_none")]
    pub expires: Option<bool>,
    #[serde(default, with = "cs_opt_fromstr", skip_serializing_if = "Option::is_none")]
    pub usage_count: Option<usize>,

    #[serde(default, with = "cs_opt_string")]
    pub location_changed: Option<Timestamp>,
}

impl From<Times> for crate::db::Times {
    fn from(t: Times) -> Self {
        crate::db::Times {
            creation: t.creation_time.as_ref().map(|ts| ts.time),
            last_modification: t.last_modification_time.as_ref().map(|ts| ts.time),
            last_access: t.last_access_time.as_ref().map(|ts| ts.time),
            expiry: t.expiry_time.as_ref().map(|ts| ts.time),
            location_changed: t.location_changed.as_ref().map(|ts| ts.time),
            expires: t.expires,
            usage_count: t.usage_count,
        }
    }
}

impl From<crate::db::Times> for Times {
    fn from(t: crate::db::Times) -> Self {
        // Use Base64 format for KDBX 4.x timestamps (matches KeePassXC behavior)
        let mode = TimestampMode::Base64;

        Times {
            creation_time: t.creation.map(|time| Timestamp { mode, time }),
            last_modification_time: t.last_modification.map(|time| Timestamp { mode, time }),
            last_access_time: t.last_access.map(|time| Timestamp { mode, time }),
            expiry_time: t.expiry.map(|time| Timestamp { mode, time }),
            location_changed: t.location_changed.map(|time| Timestamp { mode, time }),
            expires: t.expires,
            usage_count: t.usage_count,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_times_roundtrip_uses_base64() {
        // Deserialize ISO 8601 timestamps, convert to db::Times and back to xml_db::Times,
        // and verify the resulting timestamps serialize as Base64.
        let xml = r#"<Times>
 <CreationTime>2023-10-05T12:34:56Z</CreationTime>
 <LastModificationTime>2023-10-06T12:34:56Z</LastModificationTime>
 <LastAccessTime>2023-10-07T12:34:56Z</LastAccessTime>
 <ExpiryTime>2023-12-31T23:59:59Z</ExpiryTime>
 <Expires>True</Expires>
 <UsageCount>42</UsageCount>
 <LocationChanged>2023-10-08T12:34:56Z</LocationChanged>
 </Times>"#;
        let times: Times = quick_xml::de::from_str(xml).unwrap();
        // Convert to db layer and back
        let db_times: crate::db::Times = times.into();
        let roundtripped: Times = db_times.into();

        // All timestamps should now be Base64 mode after round-trip
        match roundtripped.creation_time.as_ref().unwrap().mode {
            TimestampMode::Base64 => (),
            _ => panic!("Expected Base64 mode for creation_time after round-trip"),
        }
        match roundtripped.last_modification_time.as_ref().unwrap().mode {
            TimestampMode::Base64 => (),
            _ => panic!("Expected Base64 mode for last_modification_time after round-trip"),
        }

        // Verify serialized output contains Base64 (not ISO 8601)
        let serialized = quick_xml::se::to_string(&roundtripped).unwrap();
        // Base64 timestamps don't contain dashes like "2023-10-05"
        assert!(
            !serialized.contains("2023-10-05"),
            "Round-tripped timestamps should be Base64, not ISO 8601. Got: {}",
            serialized
        );
    }

    #[test]
    fn test_deserialize_times() {
        let xml = r#"<Times>
 <CreationTime>2023-10-05T12:34:56Z</CreationTime>
 <LastModificationTime>2023-10-06T12:34:56Z</LastModificationTime>
 <LastAccessTime>2023-10-07T12:34:56Z</LastAccessTime>
 <ExpiryTime>2023-12-31T23:59:59Z</ExpiryTime>
 <Expires>True</Expires>
 <UsageCount>42</UsageCount>
 <LocationChanged>2023-10-08T12:34:56Z</LocationChanged>
 </Times>"#;
        let times: Times = quick_xml::de::from_str(xml).unwrap();
        assert_eq!(times.usage_count, Some(42));
        assert_eq!(times.expires, Some(true));

        assert_eq!(
            times.creation_time.unwrap().time,
            chrono::NaiveDateTime::parse_from_str("2023-10-05T12:34:56", "%Y-%m-%dT%H:%M:%S").unwrap()
        );

        assert_eq!(
            times.last_modification_time.unwrap().time,
            chrono::NaiveDateTime::parse_from_str("2023-10-06T12:34:56", "%Y-%m-%dT%H:%M:%S").unwrap()
        );

        assert_eq!(
            times.last_access_time.unwrap().time,
            chrono::NaiveDateTime::parse_from_str("2023-10-07T12:34:56", "%Y-%m-%dT%H:%M:%S").unwrap()
        );

        assert_eq!(
            times.expiry_time.unwrap().time,
            chrono::NaiveDateTime::parse_from_str("2023-12-31T23:59:59", "%Y-%m-%dT%H:%M:%S").unwrap()
        );

        assert_eq!(
            times.location_changed.unwrap().time,
            chrono::NaiveDateTime::parse_from_str("2023-10-08T12:34:56", "%Y-%m-%dT%H:%M:%S").unwrap()
        );
    }
}
