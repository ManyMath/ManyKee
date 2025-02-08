import 'package:flutter/material.dart';

import '../models/vault_entry.dart';
import '../state/clipboard_manager.dart';
import '../theme/spacing.dart';
import 'copy_button.dart';

/// Entry list panel showing entries for the currently selected group.
///
/// Displays a group header with entry count, two-line ListTiles
/// with copy buttons, and an empty state when no entries exist.
class EntryList extends StatelessWidget {
  /// Entries to display.
  final List<VaultEntry> entries;

  /// Currently selected entry, if any.
  final VaultEntry? selectedEntry;

  /// Callback when an entry is tapped.
  final void Function(VaultEntry) onEntrySelected;

  /// Name of the current group (shown in header).
  final String groupName;

  /// Clipboard manager for copy operations.
  final ClipboardManager clipboardManager;

  /// Callback to fetch a password by entry UUID (on-demand).
  final Future<String> Function(String entryUuid) fetchPassword;

  const EntryList({
    super.key,
    required this.entries,
    this.selectedEntry,
    required this.onEntrySelected,
    required this.groupName,
    required this.clipboardManager,
    required this.fetchPassword,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header with entry count badge.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  groupName,
                  style: textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.sm,
                  vertical: Spacing.xs,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outline),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${entries.length}',
                  style: textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Entry list or empty state.
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No entries',
                        style: textTheme.titleMedium,
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        'This group is empty.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final isSelected =
                        selectedEntry?.uuid == entry.uuid;
                    return _EntryTile(
                      entry: entry,
                      isSelected: isSelected,
                      onTap: () => onEntrySelected(entry),
                      clipboardManager: clipboardManager,
                      fetchPassword: fetchPassword,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// A single entry row with avatar, title/username, and copy buttons.
class _EntryTile extends StatelessWidget {
  final VaultEntry entry;
  final bool isSelected;
  final VoidCallback onTap;
  final ClipboardManager clipboardManager;
  final Future<String> Function(String entryUuid) fetchPassword;

  const _EntryTile({
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.clipboardManager,
    required this.fetchPassword,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final firstLetter =
        entry.title.isNotEmpty ? entry.title[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primary.withValues(alpha: 0.08)
            : null,
        border: isSelected
            ? Border(
                left: BorderSide(
                  color: colorScheme.primary,
                  width: 3,
                ),
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Row(
              children: [
                // Leading circle avatar.
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    firstLetter,
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                // Title and username.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.username.isNotEmpty)
                        Text(
                          entry.username,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Copy username button.
                CopyButton(
                  value: entry.username,
                  clipboardManager: clipboardManager,
                  icon: Icons.person_outline,
                  tooltip: 'Copy username',
                ),
                // Copy password button (lazy fetch).
                CopyButton(
                  fetchValue: () => fetchPassword(entry.uuid),
                  clipboardManager: clipboardManager,
                  icon: Icons.key,
                  tooltip: 'Copy password',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
