import 'dart:async';

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
  final VoidCallback? onEditEntry;
  final VoidCallback? onMoveEntry;
  final VoidCallback? onDeleteEntry;

  const EntryDetail({
    super.key,
    required this.entry,
    required this.vaultState,
    required this.clipboardManager,
    this.onUrlTap,
    this.onEditEntry,
    this.onMoveEntry,
    this.onDeleteEntry,
  });

  @override
  State<EntryDetail> createState() => _EntryDetailState();
}

class _EntryDetailState extends State<EntryDetail> {
  Map<String, dynamic>? _fields;
  Map<String, dynamic>? _totp;
  bool _loading = true;
  String? _error;
  Timer? _totpTimer;

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

  @override
  void dispose() {
    _totpTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFields() async {
    _totpTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _fields = null;
      _totp = null;
    });
    try {
      final fields = await widget.vaultState.readEntryFields(
        widget.entry.uuid,
      );
      Map<String, dynamic>? totp;
      try {
        totp = await widget.vaultState.getTotpCode(widget.entry.uuid);
      } catch (_) {
        totp = null;
      }
      if (mounted) {
        setState(() {
          _fields = fields;
          _totp = totp;
          _loading = false;
        });
        _scheduleTotpRefresh();
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

  void _scheduleTotpRefresh() {
    _totpTimer?.cancel();
    if (_totp == null) {
      return;
    }

    _totpTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final liveRemaining = (_totp?['valid_for'] as num?)?.toInt();
      if (liveRemaining == null) {
        timer.cancel();
        return;
      }

      if (liveRemaining <= 1) {
        timer.cancel();
        try {
          final refreshedTotp = await widget.vaultState.getTotpCode(
            widget.entry.uuid,
          );
          if (!mounted) {
            return;
          }
          setState(() {
            _totp = refreshedTotp;
          });
          _scheduleTotpRefresh();
        } catch (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _totp = null;
          });
        }
        return;
      }

      setState(() {
        _totp = <String, dynamic>{
          ...?_totp,
          'valid_for': liveRemaining - 1,
        };
      });
    });
  }

  String _formatTotpCode(String code) {
    if (code.length != 6) {
      return code;
    }
    return '${code.substring(0, 3)} ${code.substring(3)}';
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
      tags = tagsRaw
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
    } else if (tagsRaw is List) {
      tags = tagsRaw.map((t) => t.toString()).toList();
    }

    final customFields = <String, String>{};
    final rawCustomData = fields['custom_data'];
    if (rawCustomData is Map) {
      for (final entry in rawCustomData.entries) {
        if (entry.key.toString() == 'otp') {
          continue;
        }
        customFields[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }
    for (final key in fields.keys) {
      if (key == 'custom_data') {
        continue;
      }
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
    final totpCode = _totp?['code'] as String?;
    final totpValidFor = (_totp?['valid_for'] as num?)?.toInt();
    final totpPeriod = (_totp?['period'] as num?)?.toInt();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: textTheme.titleLarge),
              ),
              if (widget.onEditEntry != null)
                IconButton(
                  tooltip: 'Edit Entry',
                  onPressed: widget.onEditEntry,
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (widget.onMoveEntry != null)
                IconButton(
                  tooltip: 'Move Entry',
                  onPressed: widget.onMoveEntry,
                  icon: const Icon(Icons.drive_file_move_outline),
                ),
              if (widget.onDeleteEntry != null)
                IconButton(
                  tooltip: 'Delete Entry',
                  onPressed: widget.onDeleteEntry,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
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
          if (notes.isNotEmpty) ...[
            _FieldLabel(label: 'Notes'),
            Text(
              notes,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.lg),
          ],
          if (totpCode != null &&
              totpValidFor != null &&
              totpPeriod != null) ...[
            _FieldLabel(label: 'One-Time Code'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatTotpCode(totpCode),
                        style: textTheme.headlineSmall?.copyWith(
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'Refreshes in ${totpValidFor}s of ${totpPeriod}s',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                CopyButton(
                  value: totpCode,
                  clipboardManager: widget.clipboardManager,
                  tooltip: 'Copy one-time code',
                ),
              ],
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
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
