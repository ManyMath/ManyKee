//! A small reader for `keepassxc-cli export` XML, so tests can check what
//! KeePassXC itself reads from a database rather than going back through
//! keepass-rs.

#[derive(Debug, Default)]
pub struct Element {
    pub name: String,
    pub text: String,
    pub children: Vec<Element>,
}

impl Element {
    pub fn children_named<'a>(&'a self, name: &'a str) -> impl Iterator<Item = &'a Element> {
        self.children.iter().filter(move |child| child.name == name)
    }

    pub fn child(&self, name: &str) -> Option<&Element> {
        self.children.iter().find(|child| child.name == name)
    }

    pub fn child_text(&self, name: &str) -> Option<&str> {
        self.child(name).map(|child| child.text.as_str())
    }

    /// The value of the entry string field `key` (`<String><Key>..</Key>
    /// <Value>..</Value></String>`).
    pub fn entry_string(&self, key: &str) -> Option<&str> {
        self.children_named("String")
            .find(|field| field.child_text("Key") == Some(key))
            .and_then(|field| field.child_text("Value"))
    }

    /// A `Times` child as `YYYY-MM-DDTHH:MM:SSZ`, whether KeePassXC wrote it
    /// as ISO 8601 (KDBX 3) or as base64 seconds since year 1 (KDBX 4).
    pub fn time(&self, name: &str) -> Option<String> {
        self.child("Times")?.child_text(name).map(normalize_time)
    }
}

/// Parses the element tree of an XML document. Handles what KeePassXC
/// writes: no comments, CDATA or entities beyond the five predefined ones.
pub fn parse(xml: &str) -> Element {
    let mut stack = vec![Element::default()];
    let mut rest = xml;
    while let Some(open) = rest.find('<') {
        let text = &rest[..open];
        stack.last_mut().unwrap().text.push_str(&unescape(text));
        let close = rest[open..].find('>').expect("unterminated tag") + open;
        let tag = &rest[open + 1..close];
        rest = &rest[close + 1..];

        if tag.starts_with('?') || tag.starts_with('!') {
            continue;
        }
        if let Some(name) = tag.strip_prefix('/') {
            let element = stack.pop().expect("unbalanced end tag");
            assert_eq!(element.name, name.trim(), "mismatched end tag");
            stack
                .last_mut()
                .expect("end tag outside the document")
                .children
                .push(element);
            continue;
        }
        let self_closing = tag.ends_with('/');
        let name = tag
            .trim_end_matches('/')
            .split_whitespace()
            .next()
            .expect("empty tag")
            .to_string();
        let element = Element {
            name,
            ..Element::default()
        };
        if self_closing {
            stack.last_mut().unwrap().children.push(element);
        } else {
            stack.push(element);
        }
    }
    assert_eq!(stack.len(), 1, "unclosed elements");
    stack
        .pop()
        .unwrap()
        .children
        .pop()
        .expect("no root element")
}

fn unescape(text: &str) -> String {
    text.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&amp;", "&")
}

fn normalize_time(value: &str) -> String {
    if value.ends_with('Z') {
        return value.to_string();
    }
    let bytes = decode_base64(value);
    let seconds = i64::from_le_bytes(bytes.try_into().expect("8-byte KDBX 4 timestamp"));
    let year_one = chrono::NaiveDate::from_ymd_opt(1, 1, 1)
        .unwrap()
        .and_hms_opt(0, 0, 0)
        .unwrap();
    (year_one + chrono::Duration::seconds(seconds))
        .format("%Y-%m-%dT%H:%M:%SZ")
        .to_string()
}

fn decode_base64(value: &str) -> Vec<u8> {
    const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut bits = 0u32;
    let mut bit_count = 0;
    let mut out = Vec::new();
    for byte in value.bytes().filter(|byte| *byte != b'=') {
        let sextet = ALPHABET
            .iter()
            .position(|candidate| *candidate == byte)
            .expect("base64 character") as u32;
        bits = (bits << 6) | sextet;
        bit_count += 6;
        if bit_count >= 8 {
            bit_count -= 8;
            out.push((bits >> bit_count) as u8);
            bits &= (1 << bit_count) - 1;
        }
    }
    out
}
