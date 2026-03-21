use crate::db::Entry;

/// An entry's history
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
