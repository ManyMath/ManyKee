use std::collections::HashMap;

use uuid::Uuid;

use crate::db::{fields, Attachment, AutoType, Color, CustomDataItem, History, Times, Value};

/// A database entry containing several key-value fields.
#[derive(Debug, Default, Eq, PartialEq, Clone)]
#[cfg_attr(feature = "serialization", derive(serde::Serialize))]
pub struct Entry {
    pub uuid: Uuid,
    pub fields: HashMap<String, Value<String>>,
    pub autotype: Option<AutoType>,
    pub tags: Vec<String>,

    pub times: Times,

    pub custom_data: HashMap<String, CustomDataItem>,

    pub icon_id: Option<usize>,
    pub custom_icon: Option<(Uuid, Vec<u8>)>,

    pub foreground_color: Option<Color>,
    pub background_color: Option<Color>,

    pub override_url: Option<String>,
    pub quality_check: Option<bool>,
    pub previous_parent_group: Option<Uuid>,

    /// Unknown XML elements preserved for round-trip fidelity.
    pub unknown_xml: Vec<crate::format::xml_db::xml_node::XmlNode>,

    pub attachments: HashMap<String, Attachment>,

    pub history: Option<History>,
}
impl Entry {
    pub fn new() -> Entry {
        Entry {
            uuid: Uuid::new_v4(),
            times: Times::new(),
            ..Default::default()
        }
    }
}

impl<'a> Entry {
    /// Get a field by name, taking care of unprotecting Protected values automatically
    pub fn get(&'a self, key: &str) -> Option<&'a str> {
        self.fields.get(key).map(|v| v.as_str())
    }

    /// Convenience method for getting the raw value of the 'otp' field
    pub fn get_raw_otp_value(&'a self) -> Option<&'a str> {
        self.get(fields::OTP).or_else(|| {
            self.custom_data.get(fields::OTP).and_then(|item| {
                item.value.as_ref().and_then(|value| match value {
                    crate::db::CustomDataValue::String(value) => Some(value.as_str()),
                    crate::db::CustomDataValue::Binary(_) => None,
                })
            })
        })
    }

    /// Convenience method for getting the value of the 'Title' field
    pub fn get_title(&'a self) -> Option<&'a str> {
        self.get(fields::TITLE)
    }

    /// Convenience method for getting the value of the 'UserName' field
    pub fn get_username(&'a self) -> Option<&'a str> {
        self.get(fields::USERNAME)
    }

    /// Convenience method for getting the value of the 'Password' field
    pub fn get_password(&'a self) -> Option<&'a str> {
        self.get(fields::PASSWORD)
    }

    /// Convenience method for getting the value of the 'URL' field
    pub fn get_url(&'a self) -> Option<&'a str> {
        self.get(fields::URL)
    }

    /// Adds the current version of the entry to the entry's history
    /// and updates the last modification timestamp.
    /// The history will only be updated if the entry has
    /// uncommitted changes.
    ///
    /// Returns whether or not a new history entry was added.
    ///
    /// This does not enforce any `HistoryMaxItems` / `HistoryMaxSize` limit;
    /// use [`Entry::update_history_with_limits`] to honor a database's
    /// [`Meta`][crate::db::Meta] settings.
    pub fn update_history(&mut self) -> bool {
        self.update_history_with_limits(None, None)
    }

    /// Like [`Entry::update_history`], but honors `HistoryMaxItems` /
    /// `HistoryMaxSize` (see [`Meta::history_max_items`][crate::db::Meta::history_max_items] /
    /// [`Meta::history_max_size`][crate::db::Meta::history_max_size]).
    ///
    /// Following the KeePass convention, a `history_max_items` of `Some(0)`
    /// disables history tracking: the entry's own state is still committed
    /// (the last-modification timestamp advances and existing history is
    /// discarded), but no snapshot is recorded. A negative or `None` limit
    /// means "unlimited".
    ///
    /// Returns whether or not a new history entry was added.
    pub fn update_history_with_limits(&mut self, history_max_items: Option<isize>, history_max_size: Option<isize>) -> bool {
        if self.history.is_none() {
            self.history = Some(History::default());
        }

        if !self.has_uncommitted_changes() {
            return false;
        }

        self.times.last_modification = Some(Times::now());

        if history_max_items == Some(0) {
            self.history.as_mut().unwrap().entries.clear();
            return false;
        }

        let mut new_history_entry = self.clone();
        new_history_entry.history.take().unwrap();

        let history = self.history.as_mut().unwrap();
        history.add_entry(new_history_entry);
        history.trim(history_max_items, history_max_size);

        true
    }

    /// A rough estimate, in bytes, of the storage this entry occupies: the
    /// sum of its field values and attachment payloads. This does not match
    /// the entry's serialized XML size exactly, but tracks its order of
    /// magnitude closely enough to enforce [`Meta::history_max_size`][crate::db::Meta::history_max_size].
    pub(crate) fn approximate_size(&self) -> u64 {
        let fields_size: u64 = self.fields.values().map(|v| v.get().len() as u64).sum();
        let attachments_size: u64 = self.attachments.values().map(|a| a.data.get().len() as u64).sum();
        fields_size + attachments_size
    }

    /// Determines if the entry was modified since the last
    /// history update.
    pub(crate) fn has_uncommitted_changes(&self) -> bool {
        if let Some(history) = self.history.as_ref() {
            if history.entries.is_empty() {
                return true;
            }

            let new_times = Times::default();

            let mut sanitized_entry = self.clone();
            sanitized_entry.times = new_times.clone();
            sanitized_entry.history.take();

            let mut last_history_entry = history.entries.first().unwrap().clone();
            last_history_entry.times = new_times.clone();
            last_history_entry.history.take();

            if sanitized_entry.eq(&last_history_entry) {
                return false;
            }
        }
        true
    }

    pub fn set(&mut self, key: impl Into<String>, value: Value<String>) {
        self.fields.insert(key.into(), value);
    }

    pub fn set_unprotected(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.set(key, Value::unprotected(value));
    }

    pub fn set_protected(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.set(key, Value::protected(value));
    }
}

#[cfg(test)]
mod entry_tests {
    use std::{thread, time};

    use crate::db::{fields, CustomDataItem, CustomDataValue, Entry, Value};

    #[test]
    fn update_history() {
        let mut entry = Entry::new();
        let mut last_modification_time = entry.times.last_modification.unwrap();

        entry.set_unprotected(fields::USERNAME, "user");

        // Making sure to wait 1 sec before update the history, to make
        // sure that we get a different modification timestamp.
        thread::sleep(time::Duration::from_secs(1));

        assert!(entry.update_history());
        assert!(entry.history.is_some());
        assert_eq!(entry.history.as_ref().unwrap().entries.len(), 1);
        assert_ne!(entry.times.last_modification.unwrap(), last_modification_time);
        last_modification_time = entry.times.last_modification.unwrap();
        thread::sleep(time::Duration::from_secs(1));

        // Updating the history without making any changes
        // should not do anything.
        assert!(!entry.update_history());
        assert!(entry.history.is_some());
        assert_eq!(entry.history.as_ref().unwrap().entries.len(), 1);
        assert_eq!(entry.times.last_modification.unwrap(), last_modification_time);

        entry.set_unprotected(fields::TITLE, "first title");

        assert!(entry.update_history());
        assert!(entry.history.is_some());
        assert_eq!(entry.history.as_ref().unwrap().entries.len(), 2);
        assert_ne!(entry.times.last_modification.unwrap(), last_modification_time);
        last_modification_time = entry.times.last_modification.unwrap();
        thread::sleep(time::Duration::from_secs(1));

        assert!(!entry.update_history());
        assert!(entry.history.is_some());
        assert_eq!(entry.history.as_ref().unwrap().entries.len(), 2);
        assert_eq!(entry.times.last_modification.unwrap(), last_modification_time);

        entry
            .fields
            .insert(fields::TITLE.to_string(), Value::unprotected("second title"));

        assert!(entry.update_history());
        assert!(entry.history.is_some());
        assert_eq!(entry.history.as_ref().unwrap().entries.len(), 3);
        assert_ne!(entry.times.last_modification.unwrap(), last_modification_time);
        last_modification_time = entry.times.last_modification.unwrap();
        thread::sleep(time::Duration::from_secs(1));

        assert!(!entry.update_history());
        assert!(entry.history.is_some());
        assert_eq!(entry.history.as_ref().unwrap().entries.len(), 3);
        assert_eq!(entry.times.last_modification.unwrap(), last_modification_time);

        let last_history_entry = entry.history.as_ref().unwrap().entries.first().unwrap();
        assert_eq!(last_history_entry.get_title().unwrap(), "second title");

        for history_entry in &entry.history.unwrap().entries {
            assert!(history_entry.history.is_none());
        }
    }

    #[test]
    fn get_raw_otp_value_falls_back_to_custom_data() {
        let otp = "otpauth://totp/ManyKee:fixture?secret=JBSWY3DPEHPK3PXP&issuer=ManyKee";
        let mut entry = Entry::new();
        entry.custom_data.insert(
            fields::OTP.to_string(),
            CustomDataItem {
                value: Some(CustomDataValue::String(otp.to_string())),
                last_modification_time: None,
            },
        );

        assert_eq!(entry.get_raw_otp_value(), Some(otp));
    }

    #[test]
    fn update_history_with_limits_enforces_max_items() {
        let mut entry = Entry::new();

        for i in 0..5 {
            entry.set_unprotected(fields::TITLE, format!("title {i}"));
            assert!(entry.update_history_with_limits(Some(2), None));
        }

        assert_eq!(entry.history.as_ref().unwrap().entries.len(), 2);
    }

    #[test]
    fn update_history_with_limits_zero_disables_history() {
        let mut entry = Entry::new();
        entry.set_unprotected(fields::TITLE, "first");
        assert!(entry.update_history());
        assert_eq!(entry.history.as_ref().unwrap().entries.len(), 1);

        entry.set_unprotected(fields::TITLE, "second");
        assert!(!entry.update_history_with_limits(Some(0), None));
        assert!(entry.history.as_ref().unwrap().entries.is_empty());
    }

    #[test]
    fn update_history_with_limits_enforces_max_size() {
        let mut entry = Entry::new();

        entry.set_unprotected(fields::TITLE, "a".repeat(100));
        assert!(entry.update_history_with_limits(None, Some(50)));

        entry.set_unprotected(fields::TITLE, "b".repeat(100));
        assert!(entry.update_history_with_limits(None, Some(50)));

        // The newest entry alone exceeds the limit, so it is kept on its
        // own and older entries are dropped.
        let history = entry.history.as_ref().unwrap();
        assert_eq!(history.entries.len(), 1);
        assert_eq!(history.entries[0].get_title().unwrap(), "b".repeat(100));
    }

    #[cfg(feature = "serialization")]
    #[test]
    fn serialization() {
        assert_eq!(
            serde_json::to_string(&Value::<String>::unprotected("ABC")).unwrap(),
            "\"ABC\"".to_string()
        );

        assert_eq!(
            serde_json::to_string(&Value::<String>::protected("ABC")).unwrap(),
            "\"ABC\"".to_string()
        );
    }
}
