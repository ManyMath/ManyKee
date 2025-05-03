import 'package:flutter/material.dart';

import '../models/vault_entry.dart';
import '../state/clipboard_manager.dart';
import '../state/vault_state.dart';
import '../theme/spacing.dart';
import 'copy_button.dart';
import 'password_field.dart';

class EntryDetail extends StatefulWidget {
 final VaultEntry entry;
 final VaultState vaultState;
 final ClipboardManager clipboardManager;
 final void Function(String url)? onUrlTap;

 const EntryDetail({
 super.key,
 required this.entry,
 required this.vaultState,
 required this.clipboardManager,
 this.onUrlTap,
 });

 @override
 State<EntryDetail> createState() => _EntryDetailState();
}

class _EntryDetailState extends State<EntryDetail> {
 Map<String, dynamic>? _fields;
 bool _loading = true;
 String? _error;

 static const _standardFields = {
 'Title',
 'UserName',
 'Password',
 'URL',
 'Notes',
 'Tags',
 };

 @override
 void initState() {
 super.initState();
 _loadFields();
 }

 @override
 void didUpdateWidget(EntryDetail oldWidget) {
 super.didUpdateWidget(oldWidget);
 if (oldWidget.entry.uuid != widget.entry.uuid) {
 _loadFields();
 }
 }

 Future<void> _loadFields() async {
 setState(() {
 _loading = true;
 _error = null;
 _fields = null;
 });
 try {
 final fields = await widget.vaultState.readEntryFields(
 widget.entry.uuid,
 );
 if (mounted) {
 setState(() {
 _fields = fields;
 _loading = false;
 });
 }
 } catch (e) {
 if (mounted) {
 setState(() {
 _error = e.toString();
 _loading = false;
 });
 }
 }
 }

 @override
 Widget build(BuildContext context) {
 final textTheme = Theme.of(context).textTheme;
 final colorScheme = Theme.of(context).colorScheme;

 if (_loading) {
 return const Center(child: CircularProgressIndicator());
 }

 if (_error != null) {
 return Center(
 child: Text(
 'Failed to load entry: $_error',
 style: textTheme.bodyMedium?.copyWith(
 color: colorScheme.error,
 ),
 ),
 );
 }

 final fields = _fields!;
 final title = fields['Title'] as String? ?? widget.entry.title;
 final username = fields['UserName'] as String? ?? '';
 final password = fields['Password'] as String? ?? '';
 final url = fields['URL'] as String? ?? widget.entry.url;
 final notes = fields['Notes'] as String? ?? '';
 final tagsRaw = fields['Tags'];

 List<String> tags = [];
 if (tagsRaw is String && tagsRaw.isNotEmpty) {
 tags = tagsRaw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
 } else if (tagsRaw is List) {
 tags = tagsRaw.map((t) => t.toString()).toList();
 }

 final customFields = <String, String>{};
 for (final key in fields.keys) {
 if (!_standardFields.contains(key)) {
 customFields[key] = fields[key]?.toString() ?? '';
 }
 }

 final urlStyle = widget.onUrlTap != null
 ? textTheme.bodyMedium?.copyWith(
 color: colorScheme.primary,
 decoration: TextDecoration.underline,
 )
 : textTheme.bodyMedium;

 return SingleChildScrollView(
 padding: const EdgeInsets.all(Spacing.lg),
 child: Column(
 crossAxisAlignment: CrossAxisAlignment.start,
 children: [
 Text(title, style: textTheme.titleLarge),
 if (url.isNotEmpty) ...[
 const SizedBox(height: Spacing.xs),
 Row(
 children: [
 Expanded(
 child: GestureDetector(
 onTap: widget.onUrlTap != null
 ? () => widget.onUrlTap!(url)
 : null,
 child: Text(
 url,
 style: urlStyle,
 overflow: TextOverflow.ellipsis,
 ),
 ),
 ),
 CopyButton(
 value: url,
 clipboardManager: widget.clipboardManager,
 tooltip: 'Copy URL',
 ),
 ],
 ),
 ],

 const SizedBox(height: Spacing.lg),

 if (username.isNotEmpty) ...[
 _FieldLabel(label: 'Username'),
 Row(
 children: [
 Expanded(
 child: Text(username, style: textTheme.bodyMedium),
 ),
 CopyButton(
 value: username,
 clipboardManager: widget.clipboardManager,
 tooltip: 'Copy username',
 ),
 ],
 ),
 const SizedBox(height: Spacing.lg),
 ],

 if (password.isNotEmpty) ...[
 _FieldLabel(label: 'Password'),
 PasswordField(
 value: password,
 clipboardManager: widget.clipboardManager,
 ),
 const SizedBox(height: Spacing.lg),
 ],

 if (url.isNotEmpty) ...[
 _FieldLabel(label: 'URL'),
 Row(
 children: [
 Expanded(
 child: GestureDetector(
 onTap: widget.onUrlTap != null
 ? () => widget.onUrlTap!(url)
 : null,
 child: Text(
 url,
 style: urlStyle,
 ),
 ),
 ),
 CopyButton(
 value: url,
 clipboardManager: widget.clipboardManager,
 tooltip: 'Copy URL',
 ),
 ],
 ),
 const SizedBox(height: Spacing.lg),
 ],

 if (notes.isNotEmpty) ...[
 _FieldLabel(label: 'Notes'),
 Text(
 notes,
 style: textTheme.bodyMedium,
 ),
 const SizedBox(height: Spacing.lg),
 ],

 for (final entry in customFields.entries) ...[
 _FieldLabel(label: entry.key),
 Row(
 children: [
 Expanded(
 child: Text(
 entry.value,
 style: textTheme.bodyMedium,
 ),
 ),
 CopyButton(
 value: entry.value,
 clipboardManager: widget.clipboardManager,
 tooltip: 'Copy ${entry.key}',
 ),
 ],
 ),
 const SizedBox(height: Spacing.lg),
 ],

 if (tags.isNotEmpty) ...[
 _FieldLabel(label: 'Tags'),
 Wrap(
 spacing: Spacing.sm,
 runSpacing: Spacing.xs,
 children: tags
 .map((tag) => Chip(
 label: Text(
 tag,
 style: textTheme.labelSmall,
 ),
 materialTapTargetSize:
 MaterialTapTargetSize.shrinkWrap,
 visualDensity: VisualDensity.compact,
 ))
 .toList(),
 ),
 ],
 ],
 ),
 );
 }
}

class EntryDetailEmpty extends StatelessWidget {
 const EntryDetailEmpty({super.key});

 @override
 Widget build(BuildContext context) {
 final textTheme = Theme.of(context).textTheme;
 final colorScheme = Theme.of(context).colorScheme;

 return Center(
 child: Text(
 'Select an entry to view its details.',
 style: textTheme.bodyMedium?.copyWith(
 color: colorScheme.onSurface.withValues(alpha: 0.4),
 ),
 ),
 );
 }
}

class _FieldLabel extends StatelessWidget {
 final String label;

 const _FieldLabel({required this.label});

 @override
 Widget build(BuildContext context) {
 return Padding(
 padding: const EdgeInsets.only(bottom: Spacing.xs),
 child: Text(
 label,
 style: Theme.of(context).textTheme.labelSmall?.copyWith(
 color: Theme.of(context)
 .colorScheme
 .onSurface
 .withValues(alpha: 0.6),
 ),
 ),
 );
 }
}
