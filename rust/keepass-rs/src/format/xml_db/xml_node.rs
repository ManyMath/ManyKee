use std::collections::{HashMap, HashSet};

use quick_xml::events::Event;
use quick_xml::Reader;

/// Represents an unknown XML element preserved for round-trip fidelity.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmlNode {
    /// The element tag name (e.g., "AnUnknownGroupField").
    pub name: String,
    /// The raw inner XML content between the open and close tags.
    pub inner_xml: String,
}

impl XmlNode {
    pub fn to_xml_string(&self) -> String {
        if self.inner_xml.is_empty() {
            format!("<{}/>", self.name)
        } else {
            format!("<{}>{}</{}>", self.name, self.inner_xml, self.name)
        }
    }
}

use serde::{Deserialize, Serialize};

impl Serialize for XmlNode {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_xml_string())
    }
}

impl<'de> Deserialize<'de> for XmlNode {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        Ok(XmlNode {
            name: String::new(),
            inner_xml: s,
        })
    }
}

// --------------------------------------------------------------------------------
// Known tag sets
// --------------------------------------------------------------------------------

fn entry_known_tags() -> HashSet<&'static str> {
    [
        "UUID",
        "IconID",
        "CustomIconUUID",
        "ForegroundColor",
        "BackgroundColor",
        "OverrideURL",
        "QualityCheck",
        "PreviousParentGroup",
        "Tags",
        "Times",
        "String",
        "Binary",
        "AutoType",
        "History",
        "CustomData",
    ]
    .iter()
    .copied()
    .collect()
}

fn group_known_tags() -> HashSet<&'static str> {
    [
        "UUID",
        "Name",
        "Tags",
        "Notes",
        "IconID",
        "CustomIconUUID",
        "Times",
        "IsExpanded",
        "DefaultAutoTypeSequence",
        "EnableAutoType",
        "EnableSearching",
        "LastTopVisibleEntry",
        "CustomData",
        "PreviousParentGroup",
        "Group",
        "Entry",
    ]
    .iter()
    .copied()
    .collect()
}

fn meta_known_tags() -> HashSet<&'static str> {
    [
        "Generator",
        "HeaderHash",
        "DatabaseName",
        "DatabaseNameChanged",
        "DatabaseDescription",
        "DatabaseDescriptionChanged",
        "DefaultUserName",
        "DefaultUserNameChanged",
        "DefaultUsername",
        "DefaultUsernameChanged",
        "MaintenanceHistoryDays",
        "Color",
        "MasterKeyChanged",
        "MasterKeyChangeRec",
        "MasterKeyChangeForce",
        "MemoryProtection",
        "CustomIcons",
        "RecycleBinEnabled",
        "RecycleBinUUID",
        "RecycleBinChanged",
        "EntryTemplatesGroup",
        "EntryTemplatesGroupChanged",
        "LastSelectedGroup",
        "LastTopVisibleGroup",
        "HistoryMaxItems",
        "HistoryMaxSize",
        "SettingsChanged",
        "Binaries",
        "CustomData",
    ]
    .iter()
    .copied()
    .collect()
}

type UnknownKey = (String, String); // (parent_type, uuid_base64)
pub type UnknownMap = HashMap<UnknownKey, Vec<XmlNode>>;

// --------------------------------------------------------------------------------
// Pre-processing
// --------------------------------------------------------------------------------

/// State for tracking unknown element accumulation during skip.
struct SkipState {
    parent_type: String,
    parent_uuid: String,
    tag_name: String,
    inner_xml: String,
    depth: u32, // depth within the skipped element (0 = direct children)
}

/// Pre-process KDBX XML: extract unknown child elements from Group, Entry, and Meta,
/// return cleaned XML and a map of unknowns.
pub fn preprocess_xml(xml_bytes: &[u8]) -> (String, UnknownMap) {
    use quick_xml::Writer;
    use std::io::Cursor;

    let mut reader = Reader::from_reader(xml_bytes);
    reader.config_mut().trim_text(false);
    let mut writer = Writer::new(Cursor::new(Vec::new()));
    let mut buf = Vec::new();
    let mut unknown_map = UnknownMap::new();

    // Parent stack: (tag_name, uuid_base64, depth_at_push)
    let mut parent_stack: Vec<(String, String, u32)> = Vec::new();
    let mut skip: Option<SkipState> = None;
    let mut capturing_uuid = false;
    let mut current_depth: u32 = 0;

    let entry_tags = entry_known_tags();
    let group_tags = group_known_tags();
    let meta_tags = meta_known_tags();

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Eof) => break,
            Err(_) => break,
            Ok(event) => {
                if let Some(ref mut ss) = skip {
                    // We're inside an unknown element being skipped
                    match &event {
                        Event::Start(e) => {
                            let raw = String::from_utf8_lossy(e.as_ref());
                            ss.inner_xml.push_str(&format!("<{}>", raw));
                            ss.depth += 1;
                        }
                        Event::End(e) => {
                            if ss.depth == 0 {
                                // End of the unknown element
                                let finished = skip.take().unwrap();
                                let key = (finished.parent_type, finished.parent_uuid);
                                unknown_map.entry(key).or_default().push(XmlNode {
                                    name: finished.tag_name,
                                    inner_xml: finished.inner_xml,
                                });
                                buf.clear();
                                continue;
                            }
                            ss.depth -= 1;
                            let name_ref = e.name();
                            let tag = String::from_utf8_lossy(name_ref.as_ref());
                            ss.inner_xml.push_str(&format!("</{}>", tag));
                        }
                        Event::Empty(e) => {
                            let raw = String::from_utf8_lossy(e.as_ref());
                            ss.inner_xml.push_str(&format!("<{}/>", raw));
                        }
                        Event::Text(e) => {
                            let text = String::from_utf8_lossy(e.as_ref());
                            ss.inner_xml.push_str(&text);
                        }
                        Event::CData(e) => {
                            let text = String::from_utf8_lossy(e.as_ref());
                            ss.inner_xml.push_str(&format!("<![CDATA[{}]]>", text));
                        }
                        _ => {}
                    }
                    buf.clear();
                    continue;
                }

                // Normal processing (not skipping)
                match &event {
                    Event::Start(e) => {
                        current_depth += 1;
                        let tag = String::from_utf8_lossy(e.name().as_ref()).to_string();
                        let is_tracked = matches!(tag.as_str(), "Group" | "Entry" | "Meta");

                        if is_tracked {
                            parent_stack.push((tag.clone(), String::new(), current_depth));
                        }

                        if tag == "UUID" && !parent_stack.is_empty() {
                            // Only capture UUID if we're a direct child of the tracked parent
                            let parent_depth = parent_stack.last().unwrap().2;
                            if current_depth == parent_depth + 1 {
                                capturing_uuid = true;
                            }
                        }

                        // Check if this is an unknown DIRECT child of a tracked parent
                        // (depth == parent_depth + 1)
                        if !is_tracked && !parent_stack.is_empty() {
                            let parent = parent_stack.last().unwrap();
                            let is_direct_child = current_depth == parent.2 + 1;

                            if is_direct_child {
                                let known = match parent.0.as_str() {
                                    "Group" => Some(&group_tags),
                                    "Entry" => Some(&entry_tags),
                                    "Meta" => Some(&meta_tags),
                                    _ => None,
                                };

                                if let Some(known_set) = known {
                                    if !known_set.contains(tag.as_str()) {
                                        // Start skipping
                                        skip = Some(SkipState {
                                            parent_type: parent.0.clone(),
                                            parent_uuid: parent.1.clone(),
                                            tag_name: tag,
                                            inner_xml: String::new(),
                                            depth: 0,
                                        });
                                        buf.clear();
                                        continue;
                                    }
                                }
                            }
                        }

                        writer.write_event(event.borrow()).ok();
                    }
                    Event::End(e) => {
                        let tag = String::from_utf8_lossy(e.name().as_ref()).to_string();
                        if matches!(tag.as_str(), "Group" | "Entry" | "Meta") {
                            parent_stack.pop();
                        }
                        current_depth -= 1;
                        capturing_uuid = false;
                        writer.write_event(event.borrow()).ok();
                    }
                    Event::Text(e) => {
                        if capturing_uuid && !parent_stack.is_empty() {
                            let uuid_text = String::from_utf8_lossy(e.as_ref()).trim().to_string();
                            if !uuid_text.is_empty() {
                                if let Some(parent) = parent_stack.last_mut() {
                                    parent.1 = uuid_text;
                                }
                            }
                        }
                        writer.write_event(event.borrow()).ok();
                    }
                    Event::Empty(e) => {
                        let tag = String::from_utf8_lossy(e.name().as_ref()).to_string();

                        if !parent_stack.is_empty() {
                            let parent = parent_stack.last().unwrap();
                            // For Empty elements, current_depth is the same as the parent's depth
                            // (since Empty doesn't push). Direct child means current_depth == parent.2.
                            let is_direct_child = current_depth == parent.2;

                            if is_direct_child {
                                let known = match parent.0.as_str() {
                                    "Group" => Some(&group_tags),
                                    "Entry" => Some(&entry_tags),
                                    "Meta" => Some(&meta_tags),
                                    _ => None,
                                };

                                if let Some(known_set) = known {
                                    if !known_set.contains(tag.as_str()) {
                                        let key = (parent.0.clone(), parent.1.clone());
                                        unknown_map.entry(key).or_default().push(XmlNode {
                                            name: tag,
                                            inner_xml: String::new(),
                                        });
                                        buf.clear();
                                        continue;
                                    }
                                }
                            }
                        }

                        writer.write_event(event.borrow()).ok();
                    }
                    _ => {
                        writer.write_event(event.borrow()).ok();
                    }
                }
            }
        }
        buf.clear();
    }

    let cleaned = String::from_utf8(writer.into_inner().into_inner()).unwrap_or_default();
    (cleaned, unknown_map)
}

// --------------------------------------------------------------------------------
// Attach unknowns to db structs
// --------------------------------------------------------------------------------

pub fn attach_unknowns(unknown_map: &UnknownMap, db: &mut crate::db::Database) {
    use base64::{engine::general_purpose as base64_engine, Engine as _};

    if let Some(nodes) = unknown_map.get(&("Meta".to_string(), String::new())) {
        db.meta.unknown_xml = nodes.clone();
    }

    for ((parent_type, uuid_b64), nodes) in unknown_map {
        if uuid_b64.is_empty() {
            continue;
        }
        if let Ok(bytes) = base64_engine::STANDARD.decode(uuid_b64) {
            if let Ok(uuid) = uuid::Uuid::from_slice(&bytes) {
                match parent_type.as_str() {
                    "Group" => {
                        if let Some(group) = db.root.group_by_uuid_mut(uuid) {
                            group.unknown_xml = nodes.clone();
                        }
                    }
                    "Entry" => {
                        if let Some(entry) = db.root.entry_by_uuid_mut(uuid) {
                            entry.unknown_xml = nodes.clone();
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

// --------------------------------------------------------------------------------
// Post-processing injection
// --------------------------------------------------------------------------------

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
pub fn inject_unknowns_into_xml(xml: &mut String, db: &crate::db::Database) {
    if !db.meta.unknown_xml.is_empty() {
        let s: String = db.meta.unknown_xml.iter().map(|n| n.to_xml_string()).collect();
        if let Some(pos) = xml.rfind("</Meta>") {
            xml.insert_str(pos, &s);
        }
    }
    inject_group_unknowns(xml, &db.root);
}

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
fn inject_group_unknowns(xml: &mut String, group: &crate::db::Group) {
    use base64::{engine::general_purpose as base64_engine, Engine as _};

    if !group.unknown_xml.is_empty() {
        let uuid_b64 = base64_engine::STANDARD.encode(group.uuid.as_bytes());
        let s: String = group.unknown_xml.iter().map(|n| n.to_xml_string()).collect();
        if let Some(uuid_pos) = xml.find(&format!("<UUID>{}</UUID>", uuid_b64)) {
            if let Some(close_pos) = find_own_close_tag(xml, uuid_pos, "<Group>", "</Group>") {
                xml.insert_str(close_pos, &s);
            }
        }
    }
    for entry in &group.entries {
        if !entry.unknown_xml.is_empty() {
            let uuid_b64 = base64_engine::STANDARD.encode(entry.uuid.as_bytes());
            let s: String = entry.unknown_xml.iter().map(|n| n.to_xml_string()).collect();
            if let Some(uuid_pos) = xml.find(&format!("<UUID>{}</UUID>", uuid_b64)) {
                if let Some(close_pos) = find_own_close_tag(xml, uuid_pos, "<Entry>", "</Entry>") {
                    xml.insert_str(close_pos, &s);
                }
            }
        }
    }
    for child_group in &group.groups {
        inject_group_unknowns(xml, child_group);
    }
}

/// Find the `close_tag` that matches the `open_tag` this UUID lives inside,
/// scanning forward from `from` (a position inside that element, e.g. its
/// `<UUID>` child) and depth-tracking any same-named nested elements -
/// child `Group`s under a `Group`, or history-revision `Entry`s under an
/// `Entry`, so the first same-named close tag isn't mistaken for the
/// element's own.
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
fn find_own_close_tag(xml: &str, from: usize, open_tag: &str, close_tag: &str) -> Option<usize> {
    let mut depth = 1i32;
    let mut pos = from;
    loop {
        let next_open = xml[pos..].find(open_tag).map(|i| pos + i);
        let next_close = xml[pos..].find(close_tag).map(|i| pos + i);
        match (next_open, next_close) {
            (Some(open_pos), Some(close_pos)) if open_pos < close_pos => {
                depth += 1;
                pos = open_pos + open_tag.len();
            }
            (_, Some(close_pos)) => {
                depth -= 1;
                if depth == 0 {
                    return Some(close_pos);
                }
                pos = close_pos + close_tag.len();
            }
            _ => return None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    #[test]
    fn test_find_own_close_tag_skips_nested_same_named_elements() {
        // A subgroup between the parent's UUID and the parent's own </Group>
        // used to make the naive "first </Group> after the UUID" search
        // return the subgroup's close tag instead of the parent's.
        let xml = "<Group><UUID>parent</UUID><Group><UUID>child</UUID></Group></Group>";
        let uuid_pos = xml.find("<UUID>parent</UUID>").unwrap();

        let close_pos = find_own_close_tag(xml, uuid_pos, "<Group>", "</Group>").unwrap();

        assert_eq!(&xml[close_pos..], "</Group>");
        assert_eq!(
            &xml[..close_pos],
            "<Group><UUID>parent</UUID><Group><UUID>child</UUID></Group>"
        );
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    #[test]
    fn test_find_own_close_tag_skips_history_revisions() {
        // History revisions share the live entry's <Entry> tag name, so a
        // naive search for the first </Entry> after the UUID would match
        // inside <History> instead of the live entry's own close tag.
        let xml = "<Entry><UUID>live</UUID><History><Entry><UUID>rev</UUID></Entry></History></Entry>";
        let uuid_pos = xml.find("<UUID>live</UUID>").unwrap();

        let close_pos = find_own_close_tag(xml, uuid_pos, "<Entry>", "</Entry>").unwrap();

        assert_eq!(&xml[close_pos..], "</Entry>");
        assert_eq!(
            &xml[..close_pos],
            "<Entry><UUID>live</UUID><History><Entry><UUID>rev</UUID></Entry></History>"
        );
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    #[test]
    fn test_inject_group_unknowns_targets_parent_not_subgroup() {
        use base64::{engine::general_purpose as base64_engine, Engine as _};

        let child = crate::db::Group::new("Child");
        let mut parent = crate::db::Group::new("Parent");
        parent.unknown_xml = vec![XmlNode {
            name: "ParentUnknown".to_string(),
            inner_xml: String::new(),
        }];
        parent.groups.push(child.clone());

        let mut xml = format!(
            "<Group><UUID>{}</UUID><Group><UUID>{}</UUID></Group></Group>",
            base64_engine::STANDARD.encode(parent.uuid.as_bytes()),
            base64_engine::STANDARD.encode(child.uuid.as_bytes()),
        );

        inject_group_unknowns(&mut xml, &parent);

        assert_eq!(
            xml,
            format!(
                "<Group><UUID>{}</UUID><Group><UUID>{}</UUID></Group><ParentUnknown/></Group>",
                base64_engine::STANDARD.encode(parent.uuid.as_bytes()),
                base64_engine::STANDARD.encode(child.uuid.as_bytes()),
            )
        );
    }

    #[test]
    fn test_xml_node_to_string() {
        let node = XmlNode {
            name: "AnUnknownField".to_string(),
            inner_xml: "<SubField>value</SubField>".to_string(),
        };
        assert_eq!(
            node.to_xml_string(),
            "<AnUnknownField><SubField>value</SubField></AnUnknownField>"
        );
    }

    #[test]
    fn test_xml_node_empty_to_string() {
        let node = XmlNode {
            name: "EmptyField".to_string(),
            inner_xml: String::new(),
        };
        assert_eq!(node.to_xml_string(), "<EmptyField/>");
    }

    #[test]
    fn test_preprocess_strips_and_captures() {
        let xml = r#"<KeePassFile><Meta><Generator>T</Generator></Meta><Root><Group><UUID>AAECAwQFBgcICQoLDA0ODw==</UUID><Name>R</Name><UnknownThing><Data>42</Data></UnknownThing><IconID>48</IconID><Entry><UUID>EBESExQVFhcYGRobHB0eHw==</UUID><UnknownEntry><X>hi</X></UnknownEntry><Tags>t</Tags></Entry></Group></Root></KeePassFile>"#;

        let (cleaned, map) = preprocess_xml(xml.as_bytes());

        assert!(
            !cleaned.contains("UnknownThing"),
            "Cleaned XML still contains UnknownThing:\n{}",
            cleaned
        );
        assert!(
            !cleaned.contains("UnknownEntry"),
            "Cleaned XML still contains UnknownEntry:\n{}",
            cleaned
        );
        assert!(cleaned.contains("<Name>R</Name>"));
        assert!(cleaned.contains("<Tags>t</Tags>"));

        let gk = ("Group".into(), "AAECAwQFBgcICQoLDA0ODw==".into());
        assert!(
            map.contains_key(&gk),
            "Missing group key. Keys: {:?}",
            map.keys().collect::<Vec<_>>()
        );
        assert_eq!(map[&gk][0].name, "UnknownThing");
        assert!(map[&gk][0].inner_xml.contains("42"));

        let ek = ("Entry".into(), "EBESExQVFhcYGRobHB0eHw==".into());
        assert!(
            map.contains_key(&ek),
            "Missing entry key. Keys: {:?}",
            map.keys().collect::<Vec<_>>()
        );
        assert_eq!(map[&ek][0].name, "UnknownEntry");
        assert!(map[&ek][0].inner_xml.contains("hi"));
    }

    #[test]
    fn test_full_parse_with_unknowns() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<KeePassFile>
 <Meta>
 <Generator>Test</Generator>
 <DatabaseName>TestDB</DatabaseName>
 <DatabaseNameChanged/>
 <DatabaseDescription/>
 <DatabaseDescriptionChanged/>
 <DefaultUsername/>
 <DefaultUsernameChanged/>
 <MaintenanceHistoryDays>365</MaintenanceHistoryDays>
 <Color/>
 <MasterKeyChanged/>
 <MasterKeyChangeRec>-1</MasterKeyChangeRec>
 <MasterKeyChangeForce>-1</MasterKeyChangeForce>
 <RecycleBinEnabled>False</RecycleBinEnabled>
 <RecycleBinUUID>AAAAAAAAAAAAAAAAAAAAAA==</RecycleBinUUID>
 <RecycleBinChanged/>
 <EntryTemplatesGroup>AAAAAAAAAAAAAAAAAAAAAA==</EntryTemplatesGroup>
 <EntryTemplatesGroupChanged/>
 <LastSelectedGroup>AAAAAAAAAAAAAAAAAAAAAA==</LastSelectedGroup>
 <LastTopVisibleGroup>AAAAAAAAAAAAAAAAAAAAAA==</LastTopVisibleGroup>
 <HistoryMaxItems>10</HistoryMaxItems>
 <HistoryMaxSize>6291456</HistoryMaxSize>
 <SettingsChanged/>
 </Meta>
 <Root>
 <Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Root</Name>
 <AnUnknownGroupField>
 <UnknownFieldData>42</UnknownFieldData>
 <MoreFieldData>asdf</MoreFieldData>
 </AnUnknownGroupField>
 <IconID>48</IconID>
 <IsExpanded>True</IsExpanded>
 <Entry>
 <UUID>EBESExQVFhcYGRobHB0eHw==</UUID>
 <IconID>0</IconID>
 <AnUnknownEntryField>
 <ASubField>
 <ASubSubField>hello</ASubSubField>
 <AnotherSubSubField/>
 </ASubField>
 </AnUnknownEntryField>
 <Tags>test</Tags>
 </Entry>
 </Group>
 <DeletedObjects/>
 </Root>
</KeePassFile>"#;

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let db = crate::format::xml_db::parse_xml(xml.as_bytes(), &[], &mut cipher).unwrap();

        assert!(!db.root.unknown_xml.is_empty(), "Root group should have unknowns");
        assert_eq!(db.root.unknown_xml[0].name, "AnUnknownGroupField");
        assert!(db.root.unknown_xml[0].inner_xml.contains("42"));

        assert!(!db.root.entries.is_empty());
        assert!(
            !db.root.entries[0].unknown_xml.is_empty(),
            "Entry should have unknowns"
        );
        assert_eq!(db.root.entries[0].unknown_xml[0].name, "AnUnknownEntryField");
        assert!(db.root.entries[0].unknown_xml[0].inner_xml.contains("hello"));
    }

    #[test]
    fn test_parse_without_unknowns() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<KeePassFile>
 <Meta>
 <Generator>Test</Generator>
 <DatabaseName>TestDB</DatabaseName>
 <DatabaseNameChanged/>
 <DatabaseDescription/>
 <DatabaseDescriptionChanged/>
 <DefaultUsername/>
 <DefaultUsernameChanged/>
 <MaintenanceHistoryDays>365</MaintenanceHistoryDays>
 <Color/>
 <MasterKeyChanged/>
 <MasterKeyChangeRec>-1</MasterKeyChangeRec>
 <MasterKeyChangeForce>-1</MasterKeyChangeForce>
 <RecycleBinEnabled>False</RecycleBinEnabled>
 <RecycleBinUUID>AAAAAAAAAAAAAAAAAAAAAA==</RecycleBinUUID>
 <RecycleBinChanged/>
 <EntryTemplatesGroup>AAAAAAAAAAAAAAAAAAAAAA==</EntryTemplatesGroup>
 <EntryTemplatesGroupChanged/>
 <LastSelectedGroup>AAAAAAAAAAAAAAAAAAAAAA==</LastSelectedGroup>
 <LastTopVisibleGroup>AAAAAAAAAAAAAAAAAAAAAA==</LastTopVisibleGroup>
 <HistoryMaxItems>10</HistoryMaxItems>
 <HistoryMaxSize>6291456</HistoryMaxSize>
 <SettingsChanged/>
 </Meta>
 <Root>
 <Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Root</Name>
 <IconID>48</IconID>
 <IsExpanded>True</IsExpanded>
 <Entry>
 <UUID>EBESExQVFhcYGRobHB0eHw==</UUID>
 <IconID>0</IconID>
 <Tags>test</Tags>
 </Entry>
 </Group>
 <DeletedObjects/>
 </Root>
</KeePassFile>"#;

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let db = crate::format::xml_db::parse_xml(xml.as_bytes(), &[], &mut cipher).unwrap();
        assert!(db.root.unknown_xml.is_empty());
        assert!(!db.root.entries.is_empty());
        assert!(db.root.entries[0].unknown_xml.is_empty());
    }
}
