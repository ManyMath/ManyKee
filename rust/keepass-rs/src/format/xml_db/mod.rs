//! XML (de)serialization for KeePass databases.
//!
//! This module provides types that mirror the ones in `crate::db`, but are tailored to closely fit
//! the XML structure of KeePass databases for easy `#[derive(Serialize, Deserialize)]`.
//!
//! See <https://keepass.info/help/download/KDBX_XML.xsd> for an XML schema.

pub mod custom_serde;
pub mod entry;
pub mod group;
pub mod meta;
pub mod times;
pub mod timestamp;
pub mod xml_node;

use serde::{Deserialize, Serialize, Serializer};

use base64::{engine::general_purpose as base64_engine, Engine as _};
use std::collections::HashMap;
use thiserror::Error;
use uuid::Uuid;

use crate::{
    crypt::ciphers::Cipher,
    format::xml_db::{
        custom_serde::cs_opt_string, entry::UnprotectError, group::Group, meta::Meta, timestamp::Timestamp,
    },
};
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
use crate::{crypt::CryptographyError, db::DatabaseSaveError};

pub fn parse_xml(
    data: &[u8],
    header_attachments: &[crate::db::Attachment],
    inner_decryptor: &mut dyn Cipher,
) -> Result<crate::db::Database, ParseXmlError> {
    // Pre-pass: extract unknown elements from the raw XML and produce a cleaned
    // version that serde can parse without errors.
    let (cleaned_xml, unknown_map) = xml_node::preprocess_xml(data)?;

    let kdbx: KeePassFile = quick_xml::de::from_reader(cleaned_xml.as_bytes())?;
    let mut db = kdbx.xml_to_db(inner_decryptor, header_attachments)?;

    // Attach the extracted unknown elements to the corresponding db structs.
    xml_node::attach_unknowns(&unknown_map, &mut db);

    // Only after `attach_unknowns`, which finds history revisions by their
    // position in the document.
    normalize_history_order(&mut db.root);

    Ok(db)
}

fn normalize_history_order(group: &mut crate::db::Group) {
    for entry in &mut group.entries {
        if let Some(history) = entry.history.as_mut() {
            history.normalize_file_order();
        }
    }
    for child in &mut group.groups {
        normalize_history_order(child);
    }
}

#[derive(Debug, Error)]
pub enum ParseXmlError {
    #[error("Error parsing XML inside KDBX: {0}")]
    Xml(#[from] quick_xml::DeError),

    #[error("Error unprotecting entry: {0}")]
    Unprotect(#[from] UnprotectError),

    #[error("Error pre-processing XML inside KDBX: {0}")]
    Preprocess(#[from] xml_node::PreprocessXmlError),
}

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
pub fn to_xml(
    db: &crate::db::Database,
    inner_encryptor: &mut dyn Cipher,
) -> Result<(Vec<u8>, Vec<crate::db::Attachment>), DatabaseSaveError> {
    let mut attachments = Vec::new();

    let kdbx = KeePassFile::db_to_xml(db, inner_encryptor, &mut attachments)?;
    let mut xml_string = quick_xml::se::to_string_with_root("KeePassFile", &kdbx)?;

    // Post-process: inject unknown XML elements back into the serialized output.
    xml_node::inject_unknowns_into_xml(&mut xml_string, db);

    Ok((xml_string.into_bytes(), attachments))
}

/// Like [`to_xml`], but embeds attachments inline as base64 `Meta/Binaries`
/// entries (KDBX3-style) instead of returning them for header/inner-header
/// storage (KDBX4-style).
///
/// On read, `KeePassFile::xml_to_db` decrypts `Meta/Binaries` entries with
/// the inner cipher *before* it walks entries to decrypt protected string
/// fields, so, since Salsa20/ChaCha20 are stream ciphers whose keystream
/// must be consumed in the same order it was produced, this must encrypt
/// binaries before it encrypts fields (unlike KDBX4, where binaries are
/// never inner-cipher-encrypted, so no such ordering constraint exists).
#[cfg(feature = "save_kdbx3")]
pub fn to_xml_inline_binaries(
    db: &crate::db::Database,
    inner_encryptor: &mut dyn Cipher,
) -> Result<Vec<u8>, DatabaseSaveError> {
    let mut ordered_attachments = Vec::new();
    collect_group_attachments_in_order(&db.root, &mut ordered_attachments);

    let binaries = ordered_attachments
        .iter()
        .enumerate()
        .map(|(id, attachment)| meta::Binary::db_to_xml(id, attachment, inner_encryptor))
        .collect::<Result<_, CryptographyError>>()?;

    // `db_to_xml` re-derives its own attachments vector (discarded below) by
    // walking the tree in the same order as `collect_group_attachments_in_order`,
    // so the `value_ref` indices it assigns to binary fields already line up
    // with `binaries` above.
    let mut discarded_attachments = Vec::new();
    let mut kdbx = KeePassFile::db_to_xml(db, inner_encryptor, &mut discarded_attachments)?;
    kdbx.meta.binaries = Some(meta::Binaries { binaries });

    let mut xml_string = quick_xml::se::to_string_with_root("KeePassFile", &kdbx)?;

    // Post-process: inject unknown XML elements back into the serialized output.
    xml_node::inject_unknowns_into_xml(&mut xml_string, db);

    Ok(xml_string.into_bytes())
}

/// Mirrors the attachment-collection order of `Group::db_to_xml`/
/// `Entry::db_to_xml`: child groups (depth-first) before this group's own
/// entries, and for each entry, its own attachments before its history
/// entries' attachments (in file order, see `History::file_order`).
#[cfg(feature = "save_kdbx3")]
fn collect_group_attachments_in_order(group: &crate::db::Group, out: &mut Vec<crate::db::Attachment>) {
    for g in &group.groups {
        collect_group_attachments_in_order(g, out);
    }
    for e in &group.entries {
        collect_entry_attachments_in_order(e, out);
    }
}

#[cfg(feature = "save_kdbx3")]
fn collect_entry_attachments_in_order(entry: &crate::db::Entry, out: &mut Vec<crate::db::Attachment>) {
    for attachment in entry.attachments.values() {
        out.push(attachment.clone());
    }
    if let Some(history) = entry.history.as_ref() {
        for history_entry in history.file_order() {
            collect_entry_attachments_in_order(history_entry, out);
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
struct KeePassFile {
    meta: Meta,
    root: Root,
}

impl KeePassFile {
    /// Convert from XML representation to database representation.
    fn xml_to_db(
        mut self,
        inner_decryptor: &mut dyn Cipher,
        header_attachments: &[crate::db::Attachment],
    ) -> Result<crate::db::Database, UnprotectError> {
        let mut db = crate::db::Database::new(Default::default());
        db.root.uuid = self.root.group.uuid.0;

        let mut attachments = header_attachments.to_vec();
        if let Some(binaries) = self.meta.binaries.take() {
            for binary in binaries.binaries {
                attachments.push(binary.xml_to_db(inner_decryptor)?);
            }
        }

        let custom_icons = self.meta.custom_icons.take();
        let custom_icons: HashMap<Uuid, Vec<u8>> = custom_icons
            .map(|ci| {
                ci.icons
                    .into_iter()
                    .map(|icon| (icon.uuid.0, icon.data))
                    .collect()
            })
            .unwrap_or_default();

        db.meta = self.meta.into();

        db.deleted_objects = self
            .root
            .deleted_objects
            .map(|del_objs| {
                del_objs
                    .objects
                    .into_iter()
                    .map(|obj| (obj.uuid.0, obj.deletion_time.map(|ts| ts.time)))
                    .collect()
            })
            .unwrap_or_default();

        self.root
            .group
            .xml_to_db_handle(&mut db.root, &attachments, &custom_icons, inner_decryptor)?;

        Ok(db)
    }

    /// Convert from database representation to XML representation.
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn db_to_xml(
        db: &crate::db::Database,
        inner_cipher: &mut dyn Cipher,
        attachments: &mut Vec<crate::db::Attachment>,
    ) -> Result<Self, CryptographyError> {
        use crate::format::xml_db::meta::Icon;

        let mut custom_icons = HashMap::new();

        let group = Group::db_to_xml(&db.root, inner_cipher, attachments, &mut custom_icons)?;

        let mut meta: Meta = db.meta.clone().into();
        meta.custom_icons
            .get_or_insert_with(Default::default)
            .icons
            .extend(custom_icons.into_iter().map(|(uuid, data)| Icon {
                uuid: UUID(uuid),
                data,
                last_modification_time: None,
            }));

        let deleted_objects = if db.deleted_objects.is_empty() {
            None
        } else {
            Some(DeletedObjects {
                objects: db
                    .deleted_objects
                    .iter()
                    .map(|(uuid, deletion_time)| DeletedObject {
                        uuid: UUID(*uuid),
                        deletion_time: deletion_time.map(Timestamp::from),
                    })
                    .collect(),
            })
        };

        Ok(KeePassFile {
            meta,
            root: Root {
                group,
                deleted_objects,
            },
        })
    }
}

/// A UUID deserialized from a Base64 string.
#[allow(clippy::upper_case_acronyms)] // Keep the name consistent with KeePass XML schema
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub struct UUID(Uuid);

impl<'de> Deserialize<'de> for UUID {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let input = String::deserialize(deserializer)?;

        let v = base64_engine::STANDARD
            .decode(input)
            .map_err(serde::de::Error::custom)?;

        let uuid = Uuid::from_slice(&v).map_err(serde::de::Error::custom)?;
        Ok(UUID(uuid))
    }
}

impl Serialize for UUID {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let b64 = base64_engine::STANDARD.encode(self.0.as_bytes());
        serializer.serialize_str(&b64)
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Root {
    #[serde(rename = "Group")]
    pub group: Group,

    #[serde(default, rename = "DeletedObjects")]
    pub deleted_objects: Option<DeletedObjects>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DeletedObjects {
    #[serde(default, rename = "DeletedObject")]
    pub objects: Vec<DeletedObject>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct DeletedObject {
    #[serde(rename = "UUID")]
    uuid: UUID,

    #[serde(default, with = "cs_opt_string")]
    deletion_time: Option<Timestamp>,
}

#[cfg(test)]
mod tests {

    use super::*;

    #[derive(Serialize, Deserialize)]
    struct Test<T>(T);

    #[test]
    fn test_deserialize_uuid() {
        let uuid_str = "AAECAwQFBgcICQoLDA0ODw==";
        let uuid: UUID = quick_xml::de::from_str(&format!("{}", uuid_str)).unwrap();
        assert_eq!(
            uuid.0.as_bytes(),
            &[0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f]
        );
    }

    #[test]
    fn test_serialize_uuid() {
        let uuid = UUID(Uuid::from_bytes([
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
        ]));
        let serialized = quick_xml::se::to_string(&Test(uuid)).unwrap();
        assert_eq!(serialized, "<Test>AAECAwQFBgcICQoLDA0ODw==</Test>");
    }

    /// A one-entry database whose `<History>` lists the given
    /// `(LastModificationTime, UserName)` revisions in document order. Each
    /// revision also carries an unknown element naming itself, to check that
    /// preserved XML stays with its revision when the history is reordered.
    fn xml_with_history(revisions: &[(&str, &str)]) -> String {
        let revisions: String = revisions
            .iter()
            .map(|(time, name)| {
                format!(
                    "<Entry><UUID>EBESExQVFhcYGRobHB0eHw==</UUID>\
                     <Times><LastModificationTime>{time}</LastModificationTime></Times>\
                     <String><Key>UserName</Key><Value>{name}</Value></String>\
                     <RevisionUnknown>{name}</RevisionUnknown></Entry>"
                )
            })
            .collect();
        format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<KeePassFile>
 <Meta>
 <Generator>Test</Generator>
 <HistoryMaxItems>10</HistoryMaxItems>
 <HistoryMaxSize>6291456</HistoryMaxSize>
 </Meta>
 <Root>
 <Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Root</Name>
 <Entry>
 <UUID>EBESExQVFhcYGRobHB0eHw==</UUID>
 <Times><LastModificationTime>2024-01-04T00:00:00Z</LastModificationTime></Times>
 <String><Key>UserName</Key><Value>current</Value></String>
 <History>{revisions}</History>
 </Entry>
 </Group>
 <DeletedObjects/>
 </Root>
</KeePassFile>"#
        )
    }

    fn history_user_names(db: &crate::db::Database) -> Vec<(String, String)> {
        db.root.entries[0]
            .history
            .as_ref()
            .unwrap()
            .get_entries()
            .iter()
            .map(|revision| {
                (
                    revision.get_username().unwrap().to_string(),
                    revision.unknown_xml[0].inner_xml.clone(),
                )
            })
            .collect()
    }

    const OLDEST_FIRST: [(&str, &str); 3] = [
        ("2024-01-01T00:00:00Z", "v1"),
        ("2024-01-02T00:00:00Z", "v2"),
        ("2024-01-03T00:00:00Z", "v3"),
    ];

    fn newest_first() -> Vec<(String, String)> {
        ["v3", "v2", "v1"]
            .iter()
            .map(|name| (name.to_string(), name.to_string()))
            .collect()
    }

    #[test]
    fn history_written_oldest_first_is_read_newest_first() {
        // KeePass and KeePassXC append to history and write it oldest-first.
        let xml = xml_with_history(&OLDEST_FIRST);
        let db = parse_xml(xml.as_bytes(), &[], &mut crate::crypt::ciphers::PlainCipher).unwrap();
        assert_eq!(history_user_names(&db), newest_first());
    }

    #[test]
    fn history_written_newest_first_by_older_versions_is_read_the_same_way() {
        let mut revisions = OLDEST_FIRST;
        revisions.reverse();
        let xml = xml_with_history(&revisions);
        let db = parse_xml(xml.as_bytes(), &[], &mut crate::crypt::ciphers::PlainCipher).unwrap();
        assert_eq!(history_user_names(&db), newest_first());
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    #[test]
    fn history_is_written_oldest_first() {
        let xml = xml_with_history(&OLDEST_FIRST);
        let db = parse_xml(xml.as_bytes(), &[], &mut crate::crypt::ciphers::PlainCipher).unwrap();

        let (written, _) = to_xml(&db, &mut crate::crypt::ciphers::PlainCipher).unwrap();
        let written = String::from_utf8(written).unwrap();
        let position = |needle: &str| written.find(needle).unwrap();
        // Each revision's own unknown element is written back inside it.
        let v1 = position("<RevisionUnknown>v1</RevisionUnknown>");
        let v2 = position("<RevisionUnknown>v2</RevisionUnknown>");
        let v3 = position("<RevisionUnknown>v3</RevisionUnknown>");
        assert!(
            v1 < v2 && v2 < v3,
            "history must be written oldest-first:\n{written}"
        );

        let reparsed = parse_xml(written.as_bytes(), &[], &mut crate::crypt::ciphers::PlainCipher).unwrap();
        assert_eq!(reparsed.root.entries[0].history, db.root.entries[0].history);
    }
}
