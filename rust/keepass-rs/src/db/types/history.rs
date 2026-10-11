use crate::db::Entry;

/// An entry's history, newest entry first.
///
/// KeePass and KeePassXC store history oldest-first in the file, and both
/// drop items from the front when they enforce `HistoryMaxItems`, so the XML
/// layer converts between the two orders (see `normalize_file_order` and
/// `file_order`).
#[derive(Debug, Default, Eq, PartialEq, Clone)]
#[cfg_attr(feature = "serialization", derive(serde::Serialize))]
pub struct History {
    pub(crate) entries: Vec<Entry>,
}

impl History {
    pub fn add_entry(&mut self, mut entry: Entry) {
        // DISCUSS: should we make sure that the last modification time is not the same
        // or older than the entry at the top of the history?
        if entry.history.is_some() {
            // Remove the history from the new history entry to avoid having
            // an exponential number of history entries.
            entry.history.take().unwrap();
        }
        self.entries.insert(0, entry);
    }

    pub fn get_entries(&self) -> &Vec<Entry> {
        &self.entries
    }

    /// Reorders entries read in file order into newest-first order.
    /// KeePass-compatible writers store history oldest-first, but earlier
    /// versions of this crate wrote it newest-first, so after reversing, the
    /// entries are also sorted (stably) by last modification time. Files of
    /// either kind load the same way.
    pub(crate) fn normalize_file_order(&mut self) {
        self.entries.reverse();
        self.entries
            .sort_by(|a, b| b.times.last_modification.cmp(&a.times.last_modification));
    }

    /// The entries in the order they are written to a file: oldest first.
    #[cfg(any(feature = "save_kdbx4", feature = "save_kdbx3"))]
    pub(crate) fn file_order(&self) -> std::iter::Rev<std::slice::Iter<'_, Entry>> {
        self.entries.iter().rev()
    }

    /// Drops the oldest entries so that the history satisfies the given
    /// `HistoryMaxItems` / `HistoryMaxSize` limits, following the KeePass
    /// convention: entries are ordered newest-first, and a `None` or
    /// negative limit means "unlimited".
    ///
    /// `max_size` is checked against [`Entry::approximate_size`], so it is
    /// an approximation of the on-disk `HistoryMaxSize` semantics rather
    /// than an exact byte count.
    pub fn trim(&mut self, max_items: Option<isize>, max_size: Option<isize>) {
        if let Some(max_items) = max_items {
            if max_items >= 0 {
                self.entries.truncate(max_items as usize);
            }
        }

        if let Some(max_size) = max_size {
            if max_size >= 0 {
                let max_size = max_size as u64;
                let mut total = 0u64;
                let mut keep = 0usize;
                for entry in &self.entries {
                    let entry_size = entry.approximate_size();
                    // Always keep at least the newest entry, even if it
                    // alone exceeds the size limit.
                    if keep > 0 && total + entry_size > max_size {
                        break;
                    }
                    total += entry_size;
                    keep += 1;
                }
                self.entries.truncate(keep);
            }
        }
    }
}

/// An entry with three history revisions, each with its own protected
/// password, attachment and modification time, for checking that history
/// survives a save/open round trip in order.
#[cfg(all(test, any(feature = "save_kdbx4", feature = "save_kdbx3")))]
pub(crate) fn entry_with_revisions() -> Entry {
    use crate::db::{fields, Attachment, Times, Value};

    let start = Times::now();
    let mut entry = Entry::new();
    entry.set_unprotected(fields::TITLE, "Demo Entry");
    let mut history = History::default();
    for n in 1..=3u8 {
        let mut revision = entry.clone();
        revision.set_protected(fields::PASSWORD, format!("secret-{n}"));
        revision.attachments.insert(
            format!("rev-{n}.bin"),
            Attachment {
                data: Value::protected(vec![n; 4]),
            },
        );
        revision.times.last_modification = Some(start + chrono::Duration::seconds(n.into()));
        history.add_entry(revision);
    }
    entry.set_protected(fields::PASSWORD, "secret-4");
    entry.times.last_modification = Some(start + chrono::Duration::seconds(4));
    entry.history = Some(history);
    entry
}

/// Asserts that `actual` has the history revisions of `expected` (built by
/// [`entry_with_revisions`]) in the same order.
#[cfg(all(test, any(feature = "save_kdbx4", feature = "save_kdbx3")))]
pub(crate) fn assert_same_revisions(actual: &Entry, expected: &Entry) {
    let actual = actual.history.as_ref().unwrap().get_entries();
    let expected = expected.history.as_ref().unwrap().get_entries();
    assert_eq!(actual.len(), expected.len());
    for (n, (actual, expected)) in actual.iter().zip(expected).enumerate() {
        assert_eq!(actual.get_password(), expected.get_password(), "revision {n}");
        assert_eq!(
            actual.times.last_modification, expected.times.last_modification,
            "revision {n}"
        );
        assert_eq!(actual.attachments.len(), 1, "revision {n}");
        for (name, attachment) in &expected.attachments {
            assert_eq!(
                actual.attachments[name].get(),
                attachment.get(),
                "revision {n} attachment {name}"
            );
        }
    }
}
