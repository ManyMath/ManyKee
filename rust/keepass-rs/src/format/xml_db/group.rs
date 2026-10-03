use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
use crate::crypt::CryptographyError;
use crate::{
    crypt::ciphers::Cipher,
    format::xml_db::{
        custom_serde::{cs_opt_bool, cs_opt_fromstr, cs_opt_string},
        entry::{Entry, UnprotectError},
        times::Times,
        UUID,
    },
};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct Group {
    #[serde(rename = "UUID")]
    pub uuid: UUID,

    pub name: String,

    #[serde(default, with = "cs_opt_string")]
    pub tags: Option<String>,

    #[serde(default, with = "cs_opt_string")]
    pub notes: Option<String>,

    #[serde(
        default,
        rename = "IconID",
        with = "cs_opt_fromstr",
        skip_serializing_if = "Option::is_none"
    )]
    pub icon_id: Option<usize>,

    #[serde(default, rename = "CustomIconUUID", skip_serializing_if = "Option::is_none")]
    pub custom_icon_uuid: Option<UUID>,

    #[serde(default)]
    pub times: Option<Times>,

    #[serde(default, with = "cs_opt_bool", skip_serializing_if = "Option::is_none")]
    pub is_expanded: Option<bool>,

    #[serde(default, with = "cs_opt_string")]
    pub default_auto_type_sequence: Option<String>,

    #[serde(default, with = "cs_opt_bool", skip_serializing_if = "Option::is_none")]
    pub enable_auto_type: Option<bool>,

    #[serde(default, with = "cs_opt_bool", skip_serializing_if = "Option::is_none")]
    pub enable_searching: Option<bool>,

    #[serde(default, with = "cs_opt_string")]
    pub last_top_visible_entry: Option<UUID>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub custom_data: Option<crate::format::xml_db::meta::CustomData>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub previous_parent_group: Option<UUID>,

    #[serde(default, rename = "$value")]
    pub children: Vec<GroupOrEntry>,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum GroupOrEntry {
    Group(Group),
    Entry(Entry),
}

impl Group {
    pub(crate) fn xml_to_db_handle(
        self,
        target: &mut crate::db::Group,
        header_attachments: &[crate::db::Attachment],
        custom_icons: &HashMap<Uuid, Vec<u8>>,
        inner_decryptor: &mut dyn Cipher,
    ) -> Result<(), UnprotectError> {
        target.name = self.name;
        target.notes = self.notes;
        target.tags = self.tags.clone();
        target.icon_id = self.icon_id;
        target.previous_parent_group = self.previous_parent_group.map(|u| u.0);

        if let Some(uuid) = self.custom_icon_uuid {
            let data = custom_icons
                .get(&uuid.0)
                .ok_or(UnprotectError::InvalidCustomIconReference(uuid.0))?;
            target.custom_icon_uuid = Some(uuid.0);
            target.custom_icon_data = Some(data.clone());
        }

        target.times = self.times.map(|t| t.into()).unwrap_or_default();
        target.is_expanded = self.is_expanded.unwrap_or_default();
        target.default_autotype_sequence = self.default_auto_type_sequence;
        target.enable_autotype = self.enable_auto_type;
        target.enable_searching = self.enable_searching;
        target.last_top_visible_entry = self.last_top_visible_entry.map(|u| u.0);

        if let Some(cd) = self.custom_data {
            target.custom_data = cd.into();
        }

        for child in self.children {
            match child {
                GroupOrEntry::Group(g) => {
                    let mut new_group = crate::db::Group {
                        uuid: g.uuid.0,
                        ..Default::default()
                    };

                    g.xml_to_db_handle(&mut new_group, header_attachments, custom_icons, inner_decryptor)?;
                    target.groups.push(new_group);
                }
                GroupOrEntry::Entry(e) => {
                    let mut new_entry = crate::db::Entry {
                        uuid: e.uuid.0,
                        ..Default::default()
                    };
                    e.xml_to_db_handle(&mut new_entry, header_attachments, custom_icons, inner_decryptor)?;
                    target.entries.push(new_entry);
                }
            }
        }

        Ok(())
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    pub(crate) fn db_to_xml(
        source: &crate::db::Group,
        inner_cipher: &mut dyn Cipher,
        attachments: &mut Vec<crate::db::Attachment>,
        custom_icons: &mut HashMap<Uuid, Vec<u8>>,
    ) -> Result<Self, CryptographyError> {
        let mut children = Vec::new();

        for g in &source.groups {
            children.push(GroupOrEntry::Group(Group::db_to_xml(
                g,
                inner_cipher,
                attachments,
                custom_icons,
            )?));
        }

        for e in &source.entries {
            children.push(GroupOrEntry::Entry(Entry::db_to_xml(
                e,
                inner_cipher,
                attachments,
                custom_icons,
            )?));
        }

        let custom_data: Option<crate::format::xml_db::meta::CustomData> = if source.custom_data.is_empty() {
            None
        } else {
            Some(source.custom_data.clone().into())
        };

        let custom_icon_uuid =
            if let (Some(uuid), Some(data)) = (source.custom_icon_uuid, source.custom_icon_data.as_ref()) {
                custom_icons.insert(uuid, data.clone());
                Some(UUID(uuid))
            } else {
                source.custom_icon_uuid.map(UUID)
            };

        Ok(Group {
            uuid: UUID(source.uuid),
            name: source.name.clone(),
            tags: source.tags.clone(),
            notes: source.notes.clone(),
            icon_id: source.icon_id,
            custom_icon_uuid,
            times: Some(source.times.clone().into()),
            is_expanded: Some(source.is_expanded),
            default_auto_type_sequence: source.default_autotype_sequence.clone(),
            enable_auto_type: source.enable_autotype,
            enable_searching: source.enable_searching,
            last_top_visible_entry: source.last_top_visible_entry.map(|eid| UUID(eid)),
            custom_data,
            previous_parent_group: source.previous_parent_group.map(UUID),
            children,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Serialize, Deserialize)]
    struct Test<T>(T);

    #[test]
    fn test_xml_to_db_handle_errors_on_unresolved_custom_icon_uuid() {
        let xml = "<Group><UUID>AAAAAAAAAAAAAAAAAAAAAA==</UUID><Name>G</Name><CustomIconUUID>AQECAgMDBAQFBQYGBwcICA==</CustomIconUUID></Group>";
        let xml_group: Test<Group> = quick_xml::de::from_str(xml).unwrap();

        let mut target = crate::db::Group::default();
        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let missing_uuid = xml_group.0.custom_icon_uuid.as_ref().unwrap().0;

        let result = xml_group
            .0
            .xml_to_db_handle(&mut target, &[], &HashMap::new(), &mut cipher);

        assert!(matches!(
            result,
            Err(UnprotectError::InvalidCustomIconReference(uuid)) if uuid == missing_uuid
        ));
    }

    #[test]
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    fn test_group_custom_icon_round_trips_through_db_to_xml_and_back() {
        let icon_uuid = Uuid::new_v4();
        let icon_bytes = vec![1, 2, 3, 4, 5];

        let mut source = crate::db::Group::new("Icon Group");
        source.custom_icon_uuid = Some(icon_uuid);
        source.custom_icon_data = Some(icon_bytes.clone());

        let mut custom_icons = HashMap::new();
        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let mut attachments = Vec::new();
        let xml_group = Group::db_to_xml(&source, &mut cipher, &mut attachments, &mut custom_icons).unwrap();

        // db_to_xml populates the shared accumulator, mirroring Entry::db_to_xml.
        assert_eq!(custom_icons.get(&icon_uuid), Some(&icon_bytes));
        assert_eq!(xml_group.custom_icon_uuid.as_ref().unwrap().0, icon_uuid);

        let mut target = crate::db::Group::default();
        xml_group
            .xml_to_db_handle(&mut target, &[], &custom_icons, &mut cipher)
            .unwrap();

        assert_eq!(target.custom_icon_uuid, Some(icon_uuid));
        assert_eq!(target.custom_icon_data, Some(icon_bytes));
    }

    #[test]
    fn test_deserialize_group_tags() {
        let xml = r#"<Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Tagged Group</Name>
 <Tags>tag1;tag2</Tags>
 </Group>"#;

        let group: Test<Group> = quick_xml::de::from_str(xml).unwrap();
        assert_eq!(group.0.tags, Some("tag1;tag2".to_string()));
    }

    #[test]
    fn test_deserialize_group_previous_parent_group() {
        let xml = r#"<Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Moved Group</Name>
 <PreviousParentGroup>AAECAwQFBgcICQoLDA0ODw==</PreviousParentGroup>
 </Group>"#;

        let group: Test<Group> = quick_xml::de::from_str(xml).unwrap();
        assert!(group.0.previous_parent_group.is_some());
        assert_eq!(
            group.0.previous_parent_group.unwrap().0.as_bytes(),
            &[0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f]
        );
    }

    #[test]
    fn test_deserialize_group() {
        let xml = r#"<Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Example Group</Name>
 <Notes>This is a test group.</Notes>
 <IconID>48</IconID>
 <CustomIconUUID>oaKjpLGywcLR0tPU1dbX2A==</CustomIconUUID>
 <Times>
 <CreationTime>2023-10-05T12:34:56Z</CreationTime>
 <LastModificationTime>2023-10-06T12:34:56Z</LastModificationTime>
 <LastAccessTime>2023-10-07T12:34:56Z</LastAccessTime>
 <ExpiryTime>2023-12-31T23:59:59Z</ExpiryTime>
 <Expires>True</Expires>
 <UsageCount>42</UsageCount>
 <LocationChanged>2023-10-08T12:34:56Z</LocationChanged>
 </Times>
 <IsExpanded>True</IsExpanded>
 <DefaultAutoTypeSequence>{USERNAME}{TAB}{PASSWORD}{ENTER}</DefaultAutoTypeSequence>
 <EnableAutoType>True</EnableAutoType>
 <EnableSearching>False</EnableSearching>
 <LastTopVisibleEntry>AAECAwQFBgcICQoLDA0ODw==</LastTopVisibleEntry>
 <CustomData>
 <Item>
 <Key>example_key</Key>
 <Value>example_value</Value>
 </Item>
 </CustomData>
 <Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Sub Group</Name>
 <IsExpanded>False</IsExpanded>
 </Group>
 <Entry>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 </Entry>
 <Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Another Sub Group</Name>
 </Group>
 <Entry>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 </Entry>
 </Group>"#;

        let group: Test<Group> = quick_xml::de::from_str(xml).unwrap();
        assert_eq!(group.0.uuid.0.to_string(), "00010203-0405-0607-0809-0a0b0c0d0e0f");
        assert_eq!(group.0.name, "Example Group");
        assert_eq!(group.0.notes.unwrap(), "This is a test group.");
        assert_eq!(group.0.icon_id.unwrap(), 48);
        assert_eq!(
            group.0.custom_icon_uuid.unwrap().0.to_string(),
            "a1a2a3a4-b1b2-c1c2-d1d2-d3d4d5d6d7d8"
        );
        assert_eq!(group.0.is_expanded, Some(true));
        assert_eq!(
            group.0.default_auto_type_sequence.unwrap(),
            "{USERNAME}{TAB}{PASSWORD}{ENTER}"
        );
        assert_eq!(group.0.enable_auto_type.unwrap(), true);
        assert_eq!(group.0.enable_searching.unwrap(), false);
        assert_eq!(group.0.custom_data.is_some(), true);
        assert_eq!(group.0.children.len(), 4);
    }
}
