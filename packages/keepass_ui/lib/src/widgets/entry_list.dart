import 'package:flutter/material.dart';

import '../models/vault_entry.dart';
import '../state/clipboard_manager.dart';
import '../theme/spacing.dart';
import 'copy_button.dart';

class EntryList extends StatelessWidget {
 final List<VaultEntry> entries;
 final VaultEntry? selectedEntry;
 final void Function(VaultEntry) onEntrySelected;
 final String groupName;
 final ClipboardManager clipboardManager;
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
 CopyButton(
 value: entry.username,
 clipboardManager: clipboardManager,
 icon: Icons.person_outline,
 tooltip: 'Copy username',
 ),
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
