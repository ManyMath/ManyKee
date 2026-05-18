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

/// `(tag_path, identity, occurrence)`. `tag_path` names the chain of tracked
/// containers an unknown element's parent lives under, today always a
/// single element (`["Group"]`, `["Entry"]`, `["Meta"]`, or
/// `["HistoryEntry"]`), since only direct children of `Group`/`Entry`/`Meta`
/// are tracked. Generalizing this from a bare parent-type string to a path
/// is what lets a future phase track unknowns nested one level deeper (e.g.
/// `["Entry", "AutoType"]`) without inventing a new special-cased key
/// variant per container, the way `"HistoryEntry"` had to be bolted on for
/// history revisions.
///
/// `occurrence` disambiguates a malformed-but-parseable file where more than
/// one `Group`/`Entry` shares the same UUID: it's the 0-based count of how
/// many times that exact `(tag, uuid)` pair had already been seen (in
/// document order) when this one was encountered. It's always `0` for
/// `Meta` (a singleton) and `HistoryEntry` (already disambiguated by its own
/// revision index, appended directly into `identity`, see
/// `StackEntry::unknown_key`), so this only changes behavior for genuine
/// sibling UUID collisions among live `Group`/`Entry` elements. Kept as a
/// separate tuple field rather than folded into `identity` so it never has
/// to be split back out of a string shared with other `:`-joined identity
/// conventions (`CustomData` item keys, history revision indices) that are
/// themselves arbitrary/unbounded text.
type UnknownKey = (Vec<String>, String, usize); // (tag_path, identity, occurrence)
pub type UnknownMap = HashMap<UnknownKey, Vec<XmlNode>>;

// --------------------------------------------------------------------------------
// Pre-processing
// --------------------------------------------------------------------------------

/// Where a finished `SkipState`'s captured `XmlNode` should land.
enum SkipTarget {
    /// Written straight to `unknown_map` under this key, as usual.
    Map(UnknownKey),
    /// Buffered into the currently-open `CustomData` `<Item>` instead, since
    /// its final key (which needs `<Key>`) may not be known yet.
    ItemPending,
}

/// State for tracking unknown element accumulation during skip.
struct SkipState {
    target: SkipTarget,
    tag_name: String,
    inner_xml: String,
    depth: u32, // depth within the skipped element (0 = direct children)
}

/// A tracked ancestor (`Group`/`Entry`/`Meta`) on the parent stack.
struct StackEntry {
    /// The real element tag name: "Group", "Entry", or "Meta". History
    /// revisions are still tagged "Entry" here so they use the same known-tag
    /// set as the live entry, `history_index` is what distinguishes them.
    tag: String,
    uuid: String,
    depth: u32,
    /// `Some(i)` when this `Entry` is the `i`-th (0-based, document order)
    /// `<History>` revision of its enclosing live entry, rather than the
    /// live entry itself. History revisions share the live entry's UUID, so
    /// without this, unknowns from every revision would collide into one
    /// bucket keyed only by that shared UUID.
    history_index: Option<usize>,
    /// 0-based count of how many prior `Group`/`Entry` elements with this
    /// same tag and UUID have already been fully seen (i.e. had their
    /// `<UUID>` text captured) earlier in the document, see
    /// `UnknownKey`'s doc comment. Meaningless (left at `0`) for history
    /// revisions, which use `history_index` instead.
    occurrence: usize,
}

impl StackEntry {
    /// The `UnknownMap` key unknowns attached to this element should be
    /// filed under: `(["Group"|"Entry"], uuid_b64, occurrence)` normally, or
    /// `(["HistoryEntry"], "uuid_b64:index", 0)` for a history revision.
    fn unknown_key(&self) -> UnknownKey {
        match self.history_index {
            Some(index) => (
                vec!["HistoryEntry".to_string()],
                format!("{}:{}", self.uuid, index),
                0,
            ),
            None => (vec![self.tag.clone()], self.uuid.clone(), self.occurrence),
        }
    }
}

/// Direct children of a `CustomData` `<Item>` that carry known data, anything
/// else nested in an `Item` is preserved via `item_ctx`/`ItemCtx` below.
fn item_known_tags() -> HashSet<&'static str> {
    ["Key", "Value", "LastModificationTime"].iter().copied().collect()
}

/// Direct children of a `<Times>` block that carry known data.
fn times_known_tags() -> HashSet<&'static str> {
    [
        "CreationTime",
        "LastModificationTime",
        "LastAccessTime",
        "ExpiryTime",
        "Expires",
        "UsageCount",
        "LocationChanged",
    ]
    .iter()
    .copied()
    .collect()
}

/// Direct children of an `<AutoType>` block that carry known data. Unknown
/// content nested inside a known `<Association>` isn't tracked by this phase.
fn autotype_known_tags() -> HashSet<&'static str> {
    ["Enabled", "DataTransferObfuscation", "DefaultSequence", "Association"]
        .iter()
        .copied()
        .collect()
}

/// Direct children of a `<MemoryProtection>` block that carry known data.
fn memory_protection_known_tags() -> HashSet<&'static str> {
    [
        "ProtectTitle",
        "ProtectUserName",
        "ProtectUsername",
        "ProtectPassword",
        "ProtectURL",
        "ProtectNotes",
    ]
    .iter()
    .copied()
    .collect()
}

/// The fixed-shape containers (one instance per owner, not a repeated list
/// like `CustomData`/`Item`) whose own direct-child unknowns this phase
/// tracks, and which parent tag each is legal under.
fn container_known_tags(container_tag: &str) -> Option<HashSet<&'static str>> {
    match container_tag {
        "Times" => Some(times_known_tags()),
        "AutoType" => Some(autotype_known_tags()),
        "MemoryProtection" => Some(memory_protection_known_tags()),
        _ => None,
    }
}

/// Whether `container_tag` is a legal direct child of `parent_tag` that
/// should open container-unknown tracking (`ContainerCtx`).
fn opens_container(container_tag: &str, parent_tag: &str) -> bool {
    matches!(
        (container_tag, parent_tag),
        ("Times", "Group") | ("Times", "Entry") | ("AutoType", "Entry") | ("MemoryProtection", "Meta")
    )
}

/// Tracks the currently-open `<Times>`/`<AutoType>`/`<MemoryProtection>`
/// block (a direct child of a tracked `Group`/`Entry`/`Meta`/history-revision
/// `Entry`), so unknown direct children of it can be recognized. None of
/// these containers can nest inside each other or into `CustomData`/`Item`,
/// so a single `Option` (not a stack) is enough, same reasoning as
/// `CustomDataCtx`/`ItemCtx`.
struct ContainerCtx {
    /// Depth of the container element itself; its children live at `depth + 1`.
    depth: u32,
    container_tag: String,
    /// The final `UnknownMap` key for unknowns found directly inside this
    /// container: the owner's `unknown_key()` with `container_tag` appended
    /// to the tag path.
    key: UnknownKey,
}

/// Tracks the currently-open `<CustomData>` block (a direct child of a
/// tracked `Group`/`Entry`/`Meta`/history-revision `Entry`), so `<Item>`
/// elements inside it can be recognized. `CustomData` doesn't nest, so a
/// single `Option` (not a stack) is enough, the same reasoning as
/// `item_ctx` below.
struct CustomDataCtx {
    /// Depth of the `<CustomData>` element itself; its `<Item>` children live
    /// at `depth + 1`.
    depth: u32,
    /// The owning element's key, e.g. `(["Entry"], uuid_b64)`, `"CustomData"`
    /// is appended to form the final `UnknownKey` tag_path for an item.
    owner_key: UnknownKey,
}

/// Tracks the currently-open `<Item>` inside a `CustomData` block. Buffers
/// unknown child elements until `</Item>` closes, since `<Key>` (needed to
/// build the final identity) may not have been read yet when an unknown
/// sibling is first encountered, order among `Item`'s children isn't
/// guaranteed by the schema even though real files write `Key` first.
struct ItemCtx {
    /// Depth of the `<Item>` element itself; its children live at `depth + 1`.
    depth: u32,
    owner_key: UnknownKey,
    key: Option<String>,
    pending: Vec<XmlNode>,
}

/// Malformed-input errors `preprocess_xml` itself can detect, distinct from
/// the KDBX-schema errors surfaced later by serde/`xml_to_db`, this pass
/// runs over the raw document before any of that.
#[derive(Debug, thiserror::Error)]
pub enum PreprocessXmlError {
    /// A self-closing `<UUID/>` (parsed as `Event::Empty`, not `Event::Start`)
    /// on a direct child of `Group`/`Entry`/`Meta` leaves that element with
    /// no identity to key its unknown-XML (or itself, for lookups elsewhere)
    /// by, silently treating it as `""` would misattribute/drop its data
    /// the same way a genuinely malformed UUID would, so this is rejected
    /// up front instead.
    #[error("<UUID/> element must not be empty")]
    EmptyUuid,
}

/// Pre-process KDBX XML: extract unknown child elements from Group, Entry, and Meta,
/// return cleaned XML and a map of unknowns.
pub fn preprocess_xml(xml_bytes: &[u8]) -> Result<(String, UnknownMap), PreprocessXmlError> {
    use quick_xml::Writer;
    use std::io::Cursor;

    let mut reader = Reader::from_reader(xml_bytes);
    reader.config_mut().trim_text(false);
    let mut writer = Writer::new(Cursor::new(Vec::new()));
    let mut buf = Vec::new();
    let mut unknown_map = UnknownMap::new();

    let mut parent_stack: Vec<StackEntry> = Vec::new();
    let mut skip: Option<SkipState> = None;
    let mut capturing_uuid = false;
    let mut current_depth: u32 = 0;
    // Whether we're currently inside a live entry's <History> block, and how
    // many <Entry> revisions we've seen inside it so far (document order).
    // History doesn't nest, so a flat counter (reset on each <History>) is
    // enough to index revisions.
    let mut in_history = false;
    let mut history_revision_index: usize = 0;
    // Counts, per (tag, uuid), how many times a live (non-history) Group or
    // Entry with that UUID has already been fully seen, i.e. how many
    // times its `occurrence` was already assigned, so a later sibling
    // sharing the same UUID gets a distinct `UnknownKey` instead of merging
    // its unknowns into the same bucket. See `UnknownKey`'s doc comment.
    let mut uuid_occurrence_seen: HashMap<(String, String), usize> = HashMap::new();
    // CustomData/Item don't nest, so a single Option each (not a stack) is
    // enough, see `CustomDataCtx`/`ItemCtx` docs.
    let mut custom_data_ctx: Option<CustomDataCtx> = None;
    let mut item_ctx: Option<ItemCtx> = None;
    let mut capturing_item_key = false;
    // Times/AutoType/MemoryProtection don't nest, so a single Option (not a
    // stack) is enough, see `ContainerCtx` docs.
    let mut container_ctx: Option<ContainerCtx> = None;

    let entry_tags = entry_known_tags();
    let group_tags = group_known_tags();
    let meta_tags = meta_known_tags();
    let item_tags = item_known_tags();

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
                                // End of the unknown element. Its own Start
                                // event incremented `current_depth` (that
                                // happens unconditionally, before the event
                                // is recognized as unknown and dispatched
                                // here) but, since we never reach the normal
                                // Event::End handling for this tag, nothing
                                // decrements it back, do that here, or every
                                // sibling parsed after this unknown element
                                // for the rest of the document is
                                // misjudged as one level deeper than it is.
                                current_depth -= 1;
                                let finished = skip.take().unwrap();
                                let node = XmlNode {
                                    name: finished.tag_name,
                                    inner_xml: finished.inner_xml,
                                };
                                match finished.target {
                                    SkipTarget::Map(key) => {
                                        unknown_map.entry(key).or_default().push(node);
                                    }
                                    SkipTarget::ItemPending => {
                                        if let Some(ctx) = item_ctx.as_mut() {
                                            ctx.pending.push(node);
                                        }
                                    }
                                }
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

                        if tag == "History" {
                            in_history = true;
                            history_revision_index = 0;
                        }

                        if is_tracked {
                            let history_index = if tag == "Entry" && in_history {
                                let index = history_revision_index;
                                history_revision_index += 1;
                                Some(index)
                            } else {
                                None
                            };
                            parent_stack.push(StackEntry {
                                tag: tag.clone(),
                                uuid: String::new(),
                                depth: current_depth,
                                history_index,
                                occurrence: 0,
                            });
                        }

                        if tag == "UUID" && !parent_stack.is_empty() {
                            // Only capture UUID if we're a direct child of the tracked parent
                            let parent_depth = parent_stack.last().unwrap().depth;
                            if current_depth == parent_depth + 1 {
                                capturing_uuid = true;
                            }
                        }

                        // A <CustomData> that's a direct child of a tracked
                        // parent opens a new item-tracking scope. It's still
                        // written to the output normally below (it's a known
                        // tag), we just also remember we're inside it.
                        if tag == "CustomData" && !parent_stack.is_empty() {
                            let parent = parent_stack.last().unwrap();
                            if current_depth == parent.depth + 1 {
                                custom_data_ctx = Some(CustomDataCtx {
                                    depth: current_depth,
                                    owner_key: parent.unknown_key(),
                                });
                            }
                        }

                        // An <Item> that's a direct child of the open
                        // <CustomData> opens item tracking; its own unknowns
                        // are buffered (see ItemCtx) until </Item>, once its
                        // <Key> (if any) has been read.
                        if tag == "Item" {
                            if let Some(cdc) = &custom_data_ctx {
                                if current_depth == cdc.depth + 1 {
                                    item_ctx = Some(ItemCtx {
                                        depth: current_depth,
                                        owner_key: cdc.owner_key.clone(),
                                        key: None,
                                        pending: Vec::new(),
                                    });
                                }
                            }
                        }

                        if tag == "Key" {
                            if let Some(ictx) = &item_ctx {
                                if current_depth == ictx.depth + 1 {
                                    capturing_item_key = true;
                                }
                            }
                        }

                        // A <Times>/<AutoType>/<MemoryProtection> that's a
                        // direct child of a tracked parent opens tracking for
                        // unknown children nested directly inside it (not
                        // deeper, e.g. inside a known <Association>).
                        if !parent_stack.is_empty() {
                            let parent = parent_stack.last().unwrap();
                            if current_depth == parent.depth + 1 && opens_container(tag.as_str(), parent.tag.as_str()) {
                                let (mut key_path, identity, occurrence) = parent.unknown_key();
                                key_path.push(tag.clone());
                                container_ctx = Some(ContainerCtx {
                                    depth: current_depth,
                                    container_tag: tag.clone(),
                                    key: (key_path, identity, occurrence),
                                });
                            }
                        }

                        // Check if this is an unknown DIRECT child of the
                        // open container (<Times>/<AutoType>/<MemoryProtection>).
                        if let Some(cctx) = &container_ctx {
                            let is_direct_child = current_depth == cctx.depth + 1;
                            if is_direct_child {
                                let known = container_known_tags(&cctx.container_tag);
                                if let Some(known_set) = known {
                                    if !known_set.contains(tag.as_str()) {
                                        skip = Some(SkipState {
                                            target: SkipTarget::Map(cctx.key.clone()),
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

                        // Check if this is an unknown DIRECT child of the
                        // open <Item> (depth == item_depth + 1).
                        if let Some(ictx) = &item_ctx {
                            let is_direct_child = current_depth == ictx.depth + 1;
                            if is_direct_child && !item_tags.contains(tag.as_str()) {
                                skip = Some(SkipState {
                                    target: SkipTarget::ItemPending,
                                    tag_name: tag,
                                    inner_xml: String::new(),
                                    depth: 0,
                                });
                                buf.clear();
                                continue;
                            }
                        }

                        // Check if this is an unknown DIRECT child of a tracked parent
                        // (depth == parent_depth + 1)
                        if !is_tracked && !parent_stack.is_empty() {
                            let parent = parent_stack.last().unwrap();
                            let is_direct_child = current_depth == parent.depth + 1;

                            if is_direct_child {
                                let known = match parent.tag.as_str() {
                                    "Group" => Some(&group_tags),
                                    "Entry" => Some(&entry_tags),
                                    "Meta" => Some(&meta_tags),
                                    _ => None,
                                };

                                if let Some(known_set) = known {
                                    if !known_set.contains(tag.as_str()) {
                                        // Start skipping
                                        skip = Some(SkipState {
                                            target: SkipTarget::Map(parent.unknown_key()),
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
                        if tag == "History" {
                            in_history = false;
                        }
                        if matches!(tag.as_str(), "Group" | "Entry" | "Meta") {
                            parent_stack.pop();
                        }
                        if tag == "Item" {
                            if let Some(finished) = item_ctx.take() {
                                if let Some(key) = finished.key {
                                    let (mut tag_path, identity, occurrence) = finished.owner_key;
                                    tag_path.push("CustomData".to_string());
                                    let final_key = (tag_path, format!("{}:{}", identity, key), occurrence);
                                    for node in finished.pending {
                                        unknown_map.entry(final_key.clone()).or_default().push(node);
                                    }
                                }
                            }
                        }
                        if tag == "CustomData" {
                            custom_data_ctx = None;
                        }
                        if container_ctx.as_ref().is_some_and(|c| c.container_tag == tag) {
                            container_ctx = None;
                        }
                        current_depth -= 1;
                        capturing_uuid = false;
                        capturing_item_key = false;
                        writer.write_event(event.borrow()).ok();
                    }
                    Event::Text(e) => {
                        if capturing_uuid && !parent_stack.is_empty() {
                            let uuid_text = String::from_utf8_lossy(e.as_ref()).trim().to_string();
                            if !uuid_text.is_empty() {
                                if let Some(parent) = parent_stack.last_mut() {
                                    // History revisions intentionally share the
                                    // live entry's UUID (that's not a
                                    // collision to disambiguate, they already
                                    // key off `history_index` instead), so
                                    // only live Group/Entry elements consume
                                    // an occurrence slot.
                                    if parent.history_index.is_none() {
                                        let seen = uuid_occurrence_seen
                                            .entry((parent.tag.clone(), uuid_text.clone()))
                                            .or_insert(0);
                                        parent.occurrence = *seen;
                                        *seen += 1;
                                    }
                                    parent.uuid = uuid_text;
                                }
                            }
                        }
                        if capturing_item_key {
                            let key_text = String::from_utf8_lossy(e.as_ref()).trim().to_string();
                            if !key_text.is_empty() {
                                if let Some(ictx) = item_ctx.as_mut() {
                                    ictx.key = Some(key_text);
                                }
                            }
                        }
                        writer.write_event(event.borrow()).ok();
                    }
                    Event::Empty(e) => {
                        let tag = String::from_utf8_lossy(e.name().as_ref()).to_string();

                        // A self-closing `<UUID/>` as the UUID of a tracked
                        // Group/Entry/history-revision would otherwise leave
                        // `parent.uuid` as `""`, see `PreprocessXmlError::EmptyUuid`.
                        if tag == "UUID" {
                            if let Some(parent) = parent_stack.last() {
                                if current_depth == parent.depth {
                                    return Err(PreprocessXmlError::EmptyUuid);
                                }
                            }
                        }

                        if let Some(cctx) = &container_ctx {
                            let is_direct_child = current_depth == cctx.depth;
                            if is_direct_child {
                                let known = container_known_tags(&cctx.container_tag);
                                if let Some(known_set) = known {
                                    if !known_set.contains(tag.as_str()) {
                                        unknown_map.entry(cctx.key.clone()).or_default().push(XmlNode {
                                            name: tag,
                                            inner_xml: String::new(),
                                        });
                                        buf.clear();
                                        continue;
                                    }
                                }
                            }
                        }

                        if let Some(ictx) = item_ctx.as_mut() {
                            let is_direct_child = current_depth == ictx.depth;
                            if is_direct_child && !item_tags.contains(tag.as_str()) {
                                ictx.pending.push(XmlNode {
                                    name: tag,
                                    inner_xml: String::new(),
                                });
                                buf.clear();
                                continue;
                            }
                        }

                        if !parent_stack.is_empty() {
                            let parent = parent_stack.last().unwrap();
                            // For Empty elements, current_depth is the same as the parent's depth
                            // (since Empty doesn't push). Direct child means current_depth == parent.depth.
                            let is_direct_child = current_depth == parent.depth;

                            if is_direct_child {
                                let known = match parent.tag.as_str() {
                                    "Group" => Some(&group_tags),
                                    "Entry" => Some(&entry_tags),
                                    "Meta" => Some(&meta_tags),
                                    _ => None,
                                };

                                if let Some(known_set) = known {
                                    if !known_set.contains(tag.as_str()) {
                                        unknown_map.entry(parent.unknown_key()).or_default().push(XmlNode {
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
    Ok((cleaned, unknown_map))
}

// --------------------------------------------------------------------------------
// Attach unknowns to db structs
// --------------------------------------------------------------------------------

pub fn attach_unknowns(unknown_map: &UnknownMap, db: &mut crate::db::Database) {
    if let Some(nodes) = unknown_map.get(&(vec!["Meta".to_string()], String::new(), 0)) {
        db.meta.unknown_xml = nodes.clone();
    }

    for ((tag_path, identity, occurrence), nodes) in unknown_map {
        // Group/Entry/HistoryEntry identities are never legitimately empty
        // (every element has a UUID); Meta's is always empty (it's a
        // singleton). The `Meta`-only cases below (bare Meta, and
        // `[Meta, MemoryProtection]`) rely on that emptiness, so this check
        // only skips the identity-bearing arms, not those.
        if identity.is_empty() && !matches!(tag_path.first().map(String::as_str), Some("Meta")) {
            continue;
        }

        match tag_path.as_slice() {
            [tag] if tag == "Group" => {
                if let Some(uuid) = decode_uuid(identity) {
                    if let Some(group) = db.root.group_by_uuid_occurrence_mut(uuid, *occurrence) {
                        group.unknown_xml = nodes.clone();
                    }
                }
            }
            [tag] if tag == "Entry" => {
                if let Some(uuid) = decode_uuid(identity) {
                    if let Some(entry) = db.root.entry_by_uuid_occurrence_mut(uuid, *occurrence) {
                        entry.unknown_xml = nodes.clone();
                    }
                }
            }
            [owner, container] if container == "Times" => {
                let times = match owner.as_str() {
                    "Group" => decode_uuid(identity)
                        .and_then(|uuid| db.root.group_by_uuid_occurrence_mut(uuid, *occurrence))
                        .map(|group| &mut group.times),
                    "Entry" => decode_uuid(identity)
                        .and_then(|uuid| db.root.entry_by_uuid_occurrence_mut(uuid, *occurrence))
                        .map(|entry| &mut entry.times),
                    "HistoryEntry" => history_revision_mut(db, identity).map(|revision| &mut revision.times),
                    _ => None,
                };
                if let Some(times) = times {
                    times.unknown_xml = nodes.clone();
                }
            }
            [owner, container] if container == "AutoType" => {
                let autotype = match owner.as_str() {
                    "Entry" => {
                        decode_uuid(identity).and_then(|uuid| db.root.entry_by_uuid_occurrence_mut(uuid, *occurrence))
                    }
                    "HistoryEntry" => history_revision_mut(db, identity),
                    _ => None,
                }
                .and_then(|entry| entry.autotype.as_mut());
                if let Some(autotype) = autotype {
                    autotype.unknown_xml = nodes.clone();
                }
            }
            [owner, container] if owner == "Meta" && container == "MemoryProtection" => {
                if let Some(mp) = db.meta.memory_protection.as_mut() {
                    mp.unknown_xml = nodes.clone();
                }
            }
            [tag] if tag == "HistoryEntry" => {
                // identity is "uuid_base64:revision_index", see `StackEntry::unknown_key`.
                if let Some((uuid_b64, index)) = identity
                    .split_once(':')
                    .and_then(|(uuid_b64, index)| Some((uuid_b64, index.parse::<usize>().ok()?)))
                {
                    if let Some(uuid) = decode_uuid(uuid_b64) {
                        if let Some(revision) = db
                            .root
                            .entry_by_uuid_mut(uuid)
                            .and_then(|entry| entry.history.as_mut())
                            .and_then(|history| history.entries.get_mut(index))
                        {
                            revision.unknown_xml = nodes.clone();
                        }
                    }
                }
            }
            [tag, cd] if cd == "CustomData" => {
                // identity is "owner_identity:item_key", see the `Item`
                // handling in `preprocess_xml`. `owner_identity` is empty for
                // Meta, a UUID base64 string for Group/Entry, or
                // "uuid_base64:revision_index" for a history revision.
                let Some((owner_identity, item_key)) = identity.split_once(':') else {
                    continue;
                };
                let custom_data = match tag.as_str() {
                    "Meta" => Some(&mut db.meta.custom_data),
                    "Group" => decode_uuid(owner_identity)
                        .and_then(|uuid| db.root.group_by_uuid_occurrence_mut(uuid, *occurrence))
                        .map(|group| &mut group.custom_data),
                    "Entry" => decode_uuid(owner_identity)
                        .and_then(|uuid| db.root.entry_by_uuid_occurrence_mut(uuid, *occurrence))
                        .map(|entry| &mut entry.custom_data),
                    "HistoryEntry" => owner_identity
                        .split_once(':')
                        .and_then(|(uuid_b64, index)| Some((decode_uuid(uuid_b64)?, index.parse::<usize>().ok()?)))
                        .and_then(|(uuid, index)| {
                            db.root
                                .entry_by_uuid_mut(uuid)
                                .and_then(|entry| entry.history.as_mut())
                                .and_then(|history| history.entries.get_mut(index))
                        })
                        .map(|revision| &mut revision.custom_data),
                    _ => None,
                };
                if let Some(item) = custom_data.and_then(|cd| cd.get_mut(item_key)) {
                    item.unknown_xml = nodes.clone();
                }
            }
            _ => {}
        }
    }
}

/// Resolve a `"uuid_base64:revision_index"` identity (the `HistoryEntry`
/// convention, see `StackEntry::unknown_key`) to the corresponding history
/// revision.
fn history_revision_mut<'a>(db: &'a mut crate::db::Database, identity: &str) -> Option<&'a mut crate::db::Entry> {
    let (uuid_b64, index) = identity.split_once(':')?;
    let uuid = decode_uuid(uuid_b64)?;
    let index: usize = index.parse().ok()?;
    db.root
        .entry_by_uuid_mut(uuid)
        .and_then(|entry| entry.history.as_mut())
        .and_then(|history| history.entries.get_mut(index))
}

fn decode_uuid(uuid_b64: &str) -> Option<uuid::Uuid> {
    use base64::{engine::general_purpose as base64_engine, Engine as _};
    let bytes = base64_engine::STANDARD.decode(uuid_b64).ok()?;
    uuid::Uuid::from_slice(&bytes).ok()
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
    if let Some(meta_start) = xml.find("<Meta>") {
        if let Some(mut meta_end) = xml[meta_start..].find("</Meta>").map(|i| meta_start + i) {
            if let Some(mp) = db.meta.memory_protection.as_ref() {
                meta_end += inject_container_unknowns(
                    xml,
                    meta_start,
                    meta_end,
                    "MemoryProtection",
                    &mp.unknown_xml,
                );
            }
            inject_custom_data_unknowns(xml, meta_start, meta_end, &db.meta.custom_data);
        }
    }
    let mut cursor = 0;
    inject_group_unknowns(xml, &db.root, &mut cursor);
}

/// Escape the characters `quick_xml`'s text serializer escapes, so a
/// `<Key>` lookup matches the literal serialized form of `key`.
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

/// Inject each `CustomDataItem`'s preserved `unknown_xml` just before its
/// `<Item>`'s own `</Item>`, searching only the first `<CustomData>...
/// </CustomData>` block within `[region_start, region_end)`, which, thanks
/// to `custom_data` always being declared (and thus serialized) before any
/// nested `Group`/`Entry`/`History` field on `Group`/`Entry`/`Meta`, is
/// always this element's own block rather than a descendant's. Returns the
/// number of bytes inserted, so callers can adjust any position recorded
/// past `region_end`.
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
fn inject_custom_data_unknowns(
    xml: &mut String,
    region_start: usize,
    region_end: usize,
    custom_data: &std::collections::HashMap<String, crate::db::CustomDataItem>,
) -> usize {
    let Some(cd_start) = xml[region_start..region_end].find("<CustomData>").map(|i| region_start + i) else {
        return 0;
    };
    let Some(mut cd_end) = xml[cd_start..region_end].find("</CustomData>").map(|i| cd_start + i) else {
        return 0;
    };

    let mut inserted = 0usize;
    for (key, item) in custom_data {
        if item.unknown_xml.is_empty() {
            continue;
        }
        let key_tag = format!("<Key>{}</Key>", xml_escape(key));
        let Some(key_pos) = xml[cd_start..cd_end].find(&key_tag).map(|i| cd_start + i) else {
            continue;
        };
        let Some(item_close) = xml[key_pos..cd_end].find("</Item>").map(|i| key_pos + i) else {
            continue;
        };
        let s: String = item.unknown_xml.iter().map(|n| n.to_xml_string()).collect();
        xml.insert_str(item_close, &s);
        cd_end += s.len();
        inserted += s.len();
    }
    inserted
}

/// Inject `unknown_xml` just before the `</container_tag>` close tag of the
/// first `<container_tag>...</container_tag>` (or `<container_tag/>`,
/// expanded in place) found within `[region_start, region_end)`. Mirrors
/// `inject_custom_data_unknowns`'s region-scoping rationale, but for a
/// fixed-shape, non-repeated container (`Times`/`AutoType`/
/// `MemoryProtection`) rather than a keyed list of items. Returns the number
/// of bytes inserted, so callers can adjust any position recorded past
/// `region_end`.
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
fn inject_container_unknowns(
    xml: &mut String,
    region_start: usize,
    region_end: usize,
    container_tag: &str,
    unknown_xml: &[XmlNode],
) -> usize {
    if unknown_xml.is_empty() {
        return 0;
    }
    let s: String = unknown_xml.iter().map(|n| n.to_xml_string()).collect();

    let open_tag = format!("<{}>", container_tag);
    let close_tag = format!("</{}>", container_tag);
    if let Some(open_pos) = xml[region_start..region_end].find(&open_tag).map(|i| region_start + i) {
        let search_from = open_pos + open_tag.len();
        if let Some(close_pos) = xml[search_from..region_end].find(&close_tag).map(|i| search_from + i) {
            xml.insert_str(close_pos, &s);
            return s.len();
        }
        return 0;
    }

    // The container serialized as self-closing (no known fields set) -
    // expand it in place so the unknown content has somewhere to live.
    let self_close = format!("<{}/>", container_tag);
    if let Some(pos) = xml[region_start..region_end].find(&self_close).map(|i| region_start + i) {
        let replacement = format!("<{container_tag}>{s}</{container_tag}>");
        let inserted = replacement.len() - self_close.len();
        xml.replace_range(pos..pos + self_close.len(), &replacement);
        return inserted;
    }
    0
}

/// Encode `uuid` as the literal `<UUID>...</UUID>` tag text used to locate an
/// element by its child UUID field.
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
fn uuid_tag(uuid: uuid::Uuid) -> String {
    use base64::{engine::general_purpose as base64_engine, Engine as _};
    format!("<UUID>{}</UUID>", base64_engine::STANDARD.encode(uuid.as_bytes()))
}

/// Locate an element by its `<UUID>` child searching only at or after
/// `search_from`, inject `unknown_xml` (if any) just before its own close
/// tag, and return the position just past that close tag, or `search_from`
/// unchanged if the element/close tag can't be located.
///
/// Searching only forward from a monotonically-advancing cursor (rather than
/// `xml.find` from the start of the whole document, as this used to do) is
/// the key fix: earlier elements' already-injected `unknown_xml` content is
/// attacker-controlled raw text (captured verbatim, including any embedded
/// `<UUID>...</UUID>`/`<Group>`/`<Entry>` look-alike sequences in a crafted
/// CDATA payload, see the "CDATA content ... captured unescaped" item this
/// fixes) and must never be re-matched as if it were a different element
/// later in the same document.
/// Bundles an entry's preserved-unknown data for `inject_and_advance`, since
/// it's grown past the point a flat argument list stays readable.
#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
struct EntryUnknowns<'a> {
    own: &'a [XmlNode],
    custom_data: &'a std::collections::HashMap<String, crate::db::CustomDataItem>,
    times: &'a [XmlNode],
    autotype: Option<&'a [XmlNode]>,
}

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
fn inject_and_advance(
    xml: &mut String,
    uuid: uuid::Uuid,
    unknowns: EntryUnknowns<'_>,
    open_tag: &str,
    close_tag: &str,
    search_from: usize,
) -> usize {
    let tag = uuid_tag(uuid);
    let Some(uuid_pos) = xml[search_from..].find(&tag).map(|i| search_from + i) else {
        return search_from;
    };
    let Some(mut close_pos) = find_own_close_tag(xml, uuid_pos, open_tag, close_tag) else {
        return uuid_pos + tag.len();
    };
    close_pos += inject_container_unknowns(xml, uuid_pos, close_pos, "Times", unknowns.times);
    if let Some(at_unknowns) = unknowns.autotype {
        close_pos += inject_container_unknowns(xml, uuid_pos, close_pos, "AutoType", at_unknowns);
    }
    close_pos += inject_custom_data_unknowns(xml, uuid_pos, close_pos, unknowns.custom_data);
    let unknown_xml = unknowns.own;
    if unknown_xml.is_empty() {
        return close_pos + close_tag.len();
    }
    let s: String = unknown_xml.iter().map(|n| n.to_xml_string()).collect();
    xml.insert_str(close_pos, &s);
    close_pos + s.len() + close_tag.len()
}

#[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
fn inject_group_unknowns(xml: &mut String, group: &crate::db::Group, cursor: &mut usize) {
    let tag = uuid_tag(group.uuid);
    let Some(uuid_pos) = xml[*cursor..].find(&tag).map(|i| *cursor + i) else {
        return;
    };

    // Compute this group's own close tag before touching anything in its
    // subtree, so the depth-scan can't be thrown off by content we (or our
    // descendants) are about to inject.
    let mut close_pos = find_own_close_tag(xml, uuid_pos, "<Group>", "</Group>");
    if let Some(cp) = close_pos {
        let cp = cp + inject_container_unknowns(xml, uuid_pos, cp, "Times", &group.times.unknown_xml);
        close_pos = Some(cp + inject_custom_data_unknowns(xml, uuid_pos, cp, &group.custom_data));
    }
    if !group.unknown_xml.is_empty() {
        if let Some(cp) = close_pos {
            let s: String = group.unknown_xml.iter().map(|n| n.to_xml_string()).collect();
            xml.insert_str(cp, &s);
            close_pos = Some(cp + s.len());
        }
    }

    // Entries and child groups live strictly inside [uuid_pos, close_pos),
    // i.e. entirely before this group's own (just-inserted) unknown content
    // and before anything belonging to a later sibling, bound the inner
    // cursor accordingly instead of searching the whole document.
    let mut inner = uuid_pos + tag.len();
    for entry in &group.entries {
        inner = inject_and_advance(
            xml,
            entry.uuid,
            EntryUnknowns {
                own: &entry.unknown_xml,
                custom_data: &entry.custom_data,
                times: &entry.times.unknown_xml,
                autotype: entry.autotype.as_ref().map(|at| at.unknown_xml.as_slice()),
            },
            "<Entry>",
            "</Entry>",
            inner,
        );
    }
    for child_group in &group.groups {
        inject_group_unknowns(xml, child_group, &mut inner);
    }

    *cursor = match close_pos {
        Some(cp) => cp + "</Group>".len(),
        None => inner,
    };
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

        inject_group_unknowns(&mut xml, &parent, &mut 0);

        assert_eq!(
            xml,
            format!(
                "<Group><UUID>{}</UUID><Group><UUID>{}</UUID></Group><ParentUnknown/></Group>",
                base64_engine::STANDARD.encode(parent.uuid.as_bytes()),
                base64_engine::STANDARD.encode(child.uuid.as_bytes()),
            )
        );
    }

    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    #[test]
    fn test_inject_group_unknowns_ignores_uuid_lookalike_in_earlier_siblings_unknown_xml() {
        use base64::{engine::general_purpose as base64_engine, Engine as _};

        let mut sibling_one = crate::db::Group::new("SiblingOne");
        let mut sibling_two = crate::db::Group::new("SiblingTwo");

        let sibling_two_uuid_tag = format!(
            "<UUID>{}</UUID>",
            base64_engine::STANDARD.encode(sibling_two.uuid.as_bytes())
        );
        // Simulates a crafted, verbatim-captured CDATA payload embedding a
        // fake `<UUID>...</UUID>` matching a later sibling's *real* UUID
        // followed by tag-shaped text.
        sibling_one.unknown_xml = vec![XmlNode {
            name: "Poison".to_string(),
            inner_xml: format!("</Group>{}<Group>", sibling_two_uuid_tag),
        }];
        sibling_two.unknown_xml = vec![XmlNode {
            name: "RealMarker".to_string(),
            inner_xml: String::new(),
        }];

        let mut root = crate::db::Group::new("Root");
        root.groups.push(sibling_one.clone());
        root.groups.push(sibling_two.clone());

        let root_b64 = base64_engine::STANDARD.encode(root.uuid.as_bytes());
        let s1_b64 = base64_engine::STANDARD.encode(sibling_one.uuid.as_bytes());
        let s2_b64 = base64_engine::STANDARD.encode(sibling_two.uuid.as_bytes());

        let mut xml = format!(
            "<Group><UUID>{root_b64}</UUID><Group><UUID>{s1_b64}</UUID></Group><Group><UUID>{s2_b64}</UUID></Group></Group>",
        );

        let mut cursor = 0;
        inject_group_unknowns(&mut xml, &root, &mut cursor);

        // sibling_one's own poisoned content is injected as-is (it's opaque
        // preserved XML, not our concern to sanitize) ...
        let expected = format!(
            "<Group><UUID>{root_b64}</UUID>\
             <Group><UUID>{s1_b64}</UUID><Poison></Group>{sibling_two_uuid_tag}<Group></Poison></Group>\
             <Group><UUID>{s2_b64}</UUID><RealMarker/></Group></Group>",
        );
        // ... but sibling_two's *own* unknown content must land in
        // sibling_two's real element, not get swallowed into sibling_one's
        // poisoned lookalike.
        assert_eq!(xml, expected);
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

        let (cleaned, map) = preprocess_xml(xml.as_bytes()).unwrap();

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

        let gk = (vec!["Group".to_string()], "AAECAwQFBgcICQoLDA0ODw==".to_string(), 0);
        assert!(
            map.contains_key(&gk),
            "Missing group key. Keys: {:?}",
            map.keys().collect::<Vec<_>>()
        );
        assert_eq!(map[&gk][0].name, "UnknownThing");
        assert!(map[&gk][0].inner_xml.contains("42"));

        let ek = (vec!["Entry".to_string()], "EBESExQVFhcYGRobHB0eHw==".to_string(), 0);
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
    fn test_self_closing_empty_uuid_is_rejected() {
        // A self-closing <UUID/> is parsed as Event::Empty, not Event::Start,
        // so it never went through the Text-event capture that fills
        // `parent.uuid`, leaving it "" and silently discarding that
        // element's unknown-XML via `attach_unknowns`'s empty-identity skip.
        // Now rejected up front instead.
        let xml = r#"<KeePassFile><Meta><Generator>T</Generator></Meta><Root><Group><UUID/><Name>R</Name></Group></Root></KeePassFile>"#;

        let result = preprocess_xml(xml.as_bytes());

        assert!(matches!(result, Err(PreprocessXmlError::EmptyUuid)));
    }

    #[test]
    fn test_duplicate_uuid_siblings_keep_distinct_unknowns() {
        // A malformed-but-parseable file where two sibling Entries share the
        // same UUID used to merge their unknown-XML into one map bucket
        // (keyed only by (tag, uuid)), and `entry_by_uuid_mut` only ever
        // reaches the first same-UUID entry, so the second entry's unknowns
        // were silently dropped (not just misattributed), while the first
        // could end up with a merged bucket containing both entries' fields.
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<KeePassFile>
 <Meta>
 <Generator>Test</Generator>
 </Meta>
 <Root>
 <Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Root</Name>
 <Entry>
 <UUID>EBESExQVFhcYGRobHB0eHw==</UUID>
 <IconID>0</IconID>
 <FirstUnknown>one</FirstUnknown>
 <Tags>t</Tags>
 </Entry>
 <Entry>
 <UUID>EBESExQVFhcYGRobHB0eHw==</UUID>
 <IconID>0</IconID>
 <SecondUnknown>two</SecondUnknown>
 <Tags>t</Tags>
 </Entry>
 </Group>
 <DeletedObjects/>
 </Root>
</KeePassFile>"#;

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let db = crate::format::xml_db::parse_xml(xml.as_bytes(), &[], &mut cipher).unwrap();

        assert_eq!(db.root.entries.len(), 2);
        assert_eq!(db.root.entries[0].unknown_xml.len(), 1, "first entry's unknowns");
        assert_eq!(db.root.entries[0].unknown_xml[0].name, "FirstUnknown");
        assert_eq!(db.root.entries[1].unknown_xml.len(), 1, "second entry's unknowns");
        assert_eq!(db.root.entries[1].unknown_xml[0].name, "SecondUnknown");
    }

    #[test]
    fn test_duplicate_uuid_sibling_groups_keep_distinct_unknowns() {
        // Same scenario as the sibling-Entry case above, but for two
        // sibling subgroups sharing a UUID.
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<KeePassFile>
 <Meta>
 <Generator>Test</Generator>
 </Meta>
 <Root>
 <Group>
 <UUID>AAAAAAAAAAAAAAAAAAAAAA==</UUID>
 <Name>Root</Name>
 <Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>First</Name>
 <FirstUnknown>one</FirstUnknown>
 </Group>
 <Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Second</Name>
 <SecondUnknown>two</SecondUnknown>
 </Group>
 </Group>
 <DeletedObjects/>
 </Root>
</KeePassFile>"#;

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let db = crate::format::xml_db::parse_xml(xml.as_bytes(), &[], &mut cipher).unwrap();

        assert_eq!(db.root.groups.len(), 2);
        assert_eq!(db.root.groups[0].unknown_xml.len(), 1, "first group's unknowns");
        assert_eq!(db.root.groups[0].unknown_xml[0].name, "FirstUnknown");
        assert_eq!(db.root.groups[1].unknown_xml.len(), 1, "second group's unknowns");
        assert_eq!(db.root.groups[1].unknown_xml[0].name, "SecondUnknown");
    }

    #[test]
    fn test_history_revisions_keep_distinct_unknowns() {
        // History revisions share the live entry's UUID, so without
        // per-revision keying, unknowns from every revision (and the live
        // entry) collide into one bucket and only the live entry ever gets
        // them written back.
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
 <LiveEntryUnknown><V>live</V></LiveEntryUnknown>
 <Tags>test</Tags>
 <History>
 <Entry>
 <UUID>EBESExQVFhcYGRobHB0eHw==</UUID>
 <IconID>0</IconID>
 <RevisionUnknown><V>rev0</V></RevisionUnknown>
 </Entry>
 <Entry>
 <UUID>EBESExQVFhcYGRobHB0eHw==</UUID>
 <IconID>0</IconID>
 <RevisionUnknown><V>rev1</V></RevisionUnknown>
 </Entry>
 </History>
 </Entry>
 </Group>
 <DeletedObjects/>
 </Root>
</KeePassFile>"#;

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let db = crate::format::xml_db::parse_xml(xml.as_bytes(), &[], &mut cipher).unwrap();

        let entry = &db.root.entries[0];
        assert_eq!(entry.unknown_xml.len(), 1, "live entry should keep only its own unknown");
        assert_eq!(entry.unknown_xml[0].name, "LiveEntryUnknown");
        assert!(entry.unknown_xml[0].inner_xml.contains("live"));

        let history = entry.history.as_ref().expect("entry should have history");
        assert_eq!(history.entries.len(), 2);
        assert_eq!(history.entries[0].unknown_xml.len(), 1);
        assert!(history.entries[0].unknown_xml[0].inner_xml.contains("rev0"));
        assert_eq!(history.entries[1].unknown_xml.len(), 1);
        assert!(history.entries[1].unknown_xml[0].inner_xml.contains("rev1"));
    }

    #[test]
    fn test_custom_data_item_unknown_child_is_preserved_on_parse() {
        // A future/plugin-added child of a CustomData <Item> (e.g. a
        // hypothetical <Source>) used to be silently dropped: preprocess_xml
        // only tracked unknowns one level below Group/Entry/Meta, not inside
        // an already-known child like CustomData/Item.
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
 <CustomData>
 <Item>
 <Key>meta_plugin_key</Key>
 <Value>meta_value</Value>
 <PluginSource>meta-plugin</PluginSource>
 </Item>
 </CustomData>
 </Meta>
 <Root>
 <Group>
 <UUID>AAECAwQFBgcICQoLDA0ODw==</UUID>
 <Name>Root</Name>
 <IconID>48</IconID>
 <IsExpanded>True</IsExpanded>
 <CustomData>
 <Item>
 <Key>group_plugin_key</Key>
 <Value>group_value</Value>
 <PluginSource>group-plugin</PluginSource>
 </Item>
 </CustomData>
 <Entry>
 <UUID>EBESExQVFhcYGRobHB0eHw==</UUID>
 <IconID>0</IconID>
 <Tags>test</Tags>
 <CustomData>
 <Item>
 <Key>entry_plugin_key</Key>
 <Value>entry_value</Value>
 <PluginSource>entry-plugin</PluginSource>
 </Item>
 </CustomData>
 </Entry>
 </Group>
 <DeletedObjects/>
 </Root>
</KeePassFile>"#;

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let db = crate::format::xml_db::parse_xml(xml.as_bytes(), &[], &mut cipher).unwrap();

        let meta_item = db.meta.custom_data.get("meta_plugin_key").unwrap();
        assert_eq!(meta_item.unknown_xml.len(), 1);
        assert_eq!(meta_item.unknown_xml[0].name, "PluginSource");
        assert!(meta_item.unknown_xml[0].inner_xml.contains("meta-plugin"));

        let group_item = db.root.custom_data.get("group_plugin_key").unwrap();
        assert_eq!(group_item.unknown_xml.len(), 1);
        assert!(group_item.unknown_xml[0].inner_xml.contains("group-plugin"));

        let entry_item = db.root.entries[0].custom_data.get("entry_plugin_key").unwrap();
        assert_eq!(entry_item.unknown_xml.len(), 1);
        assert!(entry_item.unknown_xml[0].inner_xml.contains("entry-plugin"));
    }

    #[cfg(feature = "save_kdbx4")]
    #[test]
    fn test_custom_data_item_unknown_child_round_trips_through_save() {
        use crate::db::{CustomDataItem, CustomDataValue};

        let mut db = crate::db::Database::new(Default::default());
        db.meta.custom_data.insert(
            "meta_key".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("meta_value".to_string())),
                last_modification_time: None,
                unknown_xml: vec![XmlNode {
                    name: "PluginSource".to_string(),
                    inner_xml: "meta-plugin".to_string(),
                }],
            },
        );
        db.root.custom_data.insert(
            "group_key".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("group_value".to_string())),
                last_modification_time: None,
                unknown_xml: vec![XmlNode {
                    name: "PluginSource".to_string(),
                    inner_xml: "group-plugin".to_string(),
                }],
            },
        );
        let mut entry = crate::db::Entry::new();
        entry.custom_data.insert(
            "entry_key".to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String("entry_value".to_string())),
                last_modification_time: None,
                unknown_xml: vec![XmlNode {
                    name: "PluginSource".to_string(),
                    inner_xml: "entry-plugin".to_string(),
                }],
            },
        );
        db.root.entries.push(entry);

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let (xml_bytes, _) = crate::format::xml_db::to_xml(&db, &mut cipher).unwrap();

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let reparsed = crate::format::xml_db::parse_xml(&xml_bytes, &[], &mut cipher).unwrap();

        assert_eq!(
            reparsed.meta.custom_data.get("meta_key").unwrap().unknown_xml[0].name,
            "PluginSource"
        );
        assert!(reparsed.meta.custom_data.get("meta_key").unwrap().unknown_xml[0]
            .inner_xml
            .contains("meta-plugin"));
        assert!(reparsed.root.custom_data.get("group_key").unwrap().unknown_xml[0]
            .inner_xml
            .contains("group-plugin"));
        assert!(
            reparsed.root.entries[0].custom_data.get("entry_key").unwrap().unknown_xml[0]
                .inner_xml
                .contains("entry-plugin")
        );
    }

    #[test]
    fn test_unknown_element_does_not_shift_depth_for_later_siblings() {
        // `current_depth` was incremented on every Start event (including an
        // unknown element's own), but only decremented on a normal
        // Event::End, the finalizing End of a *skipped* unknown element
        // never went through that path, so `current_depth` stayed
        // permanently one level too deep for every sibling parsed after the
        // first unknown element in the document. A second unknown element
        // later in the same container (nested one level deeper than it
        // should be, per the drifted depth) used to go undetected, and any
        // legitimately nested known field at the drifted depth could be
        // misclassified too.
        let xml = r#"<KeePassFile><Meta><Generator>T</Generator></Meta><Root><Group><UUID>AAECAwQFBgcICQoLDA0ODw==</UUID><Name>R</Name><UnknownOne>x</UnknownOne><IconID>48</IconID><UnknownTwo>y</UnknownTwo><IsExpanded>True</IsExpanded></Group></Root></KeePassFile>"#;

        let (cleaned, map) = preprocess_xml(xml.as_bytes()).unwrap();

        assert!(cleaned.contains("<IconID>48</IconID>"));
        assert!(cleaned.contains("<IsExpanded>True</IsExpanded>"));

        let gk = (vec!["Group".to_string()], "AAECAwQFBgcICQoLDA0ODw==".to_string(), 0);
        let names: Vec<_> = map[&gk].iter().map(|n| n.name.as_str()).collect();
        assert_eq!(names, vec!["UnknownOne", "UnknownTwo"], "both unknown siblings should be captured, not just the first");
    }

    #[test]
    fn test_times_autotype_memory_protection_unknown_children_preserved_on_parse() {
        // Phase 3: unknown direct children of Times (Group and Entry),
        // AutoType (Entry), and MemoryProtection (Meta) used to be silently
        // dropped, the same way CustomData/Item unknowns were before phase 2.
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
 <MemoryProtection>
 <ProtectTitle>False</ProtectTitle>
 <ProtectUserName>False</ProtectUserName>
 <ProtectPassword>True</ProtectPassword>
 <ProtectURL>False</ProtectURL>
 <ProtectNotes>False</ProtectNotes>
 <FutureProtectionFlag>True</FutureProtectionFlag>
 </MemoryProtection>
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
 <Times>
 <CreationTime>2023-10-05T12:34:56Z</CreationTime>
 <LastModificationTime>2023-10-06T12:34:56Z</LastModificationTime>
 <LastAccessTime>2023-10-07T12:34:56Z</LastAccessTime>
 <ExpiryTime>2024-10-05T12:34:56Z</ExpiryTime>
 <Expires>False</Expires>
 <UsageCount>0</UsageCount>
 <LocationChanged>2023-10-08T12:34:56Z</LocationChanged>
 <FutureTimeFlag>group-times</FutureTimeFlag>
 </Times>
 <IsExpanded>True</IsExpanded>
 <Entry>
 <UUID>EBESExQVFhcYGRobHB0eHw==</UUID>
 <IconID>0</IconID>
 <Times>
 <CreationTime>2023-10-05T12:34:56Z</CreationTime>
 <LastModificationTime>2023-10-06T12:34:56Z</LastModificationTime>
 <LastAccessTime>2023-10-07T12:34:56Z</LastAccessTime>
 <ExpiryTime>2024-10-05T12:34:56Z</ExpiryTime>
 <Expires>False</Expires>
 <UsageCount>0</UsageCount>
 <LocationChanged>2023-10-08T12:34:56Z</LocationChanged>
 <FutureTimeFlag>entry-times</FutureTimeFlag>
 </Times>
 <Tags>test</Tags>
 <AutoType>
 <Enabled>True</Enabled>
 <DataTransferObfuscation>False</DataTransferObfuscation>
 <DefaultSequence>{USERNAME}{TAB}{PASSWORD}{ENTER}</DefaultSequence>
 <FutureAutoTypeFlag>entry-autotype</FutureAutoTypeFlag>
 </AutoType>
 </Entry>
 </Group>
 <DeletedObjects/>
 </Root>
</KeePassFile>"#;

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let db = crate::format::xml_db::parse_xml(xml.as_bytes(), &[], &mut cipher).unwrap();

        let mp = db.meta.memory_protection.as_ref().expect("memory protection present");
        assert_eq!(mp.unknown_xml.len(), 1);
        assert_eq!(mp.unknown_xml[0].name, "FutureProtectionFlag");

        assert_eq!(db.root.times.unknown_xml.len(), 1);
        assert_eq!(db.root.times.unknown_xml[0].name, "FutureTimeFlag");
        assert!(db.root.times.unknown_xml[0].inner_xml.contains("group-times"));

        let entry = &db.root.entries[0];
        assert_eq!(entry.times.unknown_xml.len(), 1);
        assert!(entry.times.unknown_xml[0].inner_xml.contains("entry-times"));

        let autotype = entry.autotype.as_ref().expect("autotype present");
        assert_eq!(autotype.unknown_xml.len(), 1);
        assert_eq!(autotype.unknown_xml[0].name, "FutureAutoTypeFlag");
        assert!(autotype.unknown_xml[0].inner_xml.contains("entry-autotype"));
    }

    #[cfg(feature = "save_kdbx4")]
    #[test]
    fn test_times_autotype_memory_protection_unknown_children_round_trip_through_save() {
        let mut db = crate::db::Database::new(Default::default());
        db.meta.memory_protection = Some(crate::db::MemoryProtection {
            unknown_xml: vec![XmlNode {
                name: "FutureProtectionFlag".to_string(),
                inner_xml: "mp".to_string(),
            }],
            ..Default::default()
        });
        db.root.times.unknown_xml = vec![XmlNode {
            name: "FutureTimeFlag".to_string(),
            inner_xml: "group-times".to_string(),
        }];

        let mut entry = crate::db::Entry::new();
        entry.times.unknown_xml = vec![XmlNode {
            name: "FutureTimeFlag".to_string(),
            inner_xml: "entry-times".to_string(),
        }];
        entry.autotype = Some(crate::db::AutoType {
            enabled: true,
            unknown_xml: vec![XmlNode {
                name: "FutureAutoTypeFlag".to_string(),
                inner_xml: "entry-autotype".to_string(),
            }],
            ..Default::default()
        });
        db.root.entries.push(entry);

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let (xml_bytes, _) = crate::format::xml_db::to_xml(&db, &mut cipher).unwrap();

        let mut cipher = crate::crypt::ciphers::PlainCipher;
        let reparsed = crate::format::xml_db::parse_xml(&xml_bytes, &[], &mut cipher).unwrap();

        let mp = reparsed.meta.memory_protection.as_ref().unwrap();
        assert_eq!(mp.unknown_xml[0].name, "FutureProtectionFlag");
        assert!(mp.unknown_xml[0].inner_xml.contains("mp"));

        assert_eq!(reparsed.root.times.unknown_xml[0].name, "FutureTimeFlag");
        assert!(reparsed.root.times.unknown_xml[0].inner_xml.contains("group-times"));

        let entry = &reparsed.root.entries[0];
        assert!(entry.times.unknown_xml[0].inner_xml.contains("entry-times"));
        assert!(entry.autotype.as_ref().unwrap().unknown_xml[0]
            .inner_xml
            .contains("entry-autotype"));
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
