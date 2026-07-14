import 'dart:math';

import 'package:flutter/material.dart';

import '../models/vault_group.dart';
import '../theme/spacing.dart';

class EntryFormResult {
  EntryFormResult({
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
  });

  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;

  Map<String, String?> toFields() {
    return <String, String?>{
      'Title': title,
      'UserName': username,
      'Password': password,
      'URL': url,
      'Notes': notes,
    };
  }

  Set<String> get protectedFields => const <String>{'Password'};
}

Future<EntryFormResult?> showEntryFormDialog(
  BuildContext context, {
  required String title,
  required String submitLabel,
  Map<String, dynamic> initialFields = const <String, dynamic>{},
  Map<String, dynamic> customFields = const <String, dynamic>{},
  Set<String> protectedCustomFields = const <String>{},
  Future<String?> Function(String fieldKey)? fetchFieldValue,
}) {
  final content = EntryFormDialog(
    title: title,
    submitLabel: submitLabel,
    initialFields: initialFields,
    customFields: customFields,
    protectedCustomFields: protectedCustomFields,
    fetchFieldValue: fetchFieldValue,
  );

  final isMobile = MediaQuery.sizeOf(context).width < 600;
  if (isMobile) {
    return showModalBottomSheet<EntryFormResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SafeArea(child: content),
        );
      },
    );
  }

  return showDialog<EntryFormResult>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: content,
        ),
      );
    },
  );
}

Future<String?> showEntryMoveDialog(
  BuildContext context, {
  required List<VaultGroup> groups,
  String? initialGroupUuid,
}) {
  final options = _flattenGroups(groups);
  if (options.isEmpty) {
    return Future<String?>.value(null);
  }

  final content = _MoveEntryDialog(
    options: options,
    initialGroupUuid: initialGroupUuid,
  );
  final isMobile = MediaQuery.sizeOf(context).width < 600;
  if (isMobile) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(child: content),
    );
  }

  return showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: content,
      ),
    ),
  );
}

Future<bool> showEntryDeleteConfirmation(BuildContext context) async {
  final isMobile = MediaQuery.sizeOf(context).width < 600;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text(
          'This moves the entry out of the current list. '
          'If the recycle bin is disabled, the delete is permanent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete Entry'),
          ),
        ],
      );
    },
  );

  if (isMobile) {
    FocusScope.of(context).unfocus();
  }
  return result ?? false;
}

class EntryFormDialog extends StatefulWidget {
  const EntryFormDialog({
    super.key,
    required this.title,
    required this.submitLabel,
    this.initialFields = const <String, dynamic>{},
    this.customFields = const <String, dynamic>{},
    this.protectedCustomFields = const <String>{},
    this.fetchFieldValue,
  });

  final String title;
  final String submitLabel;
  final Map<String, dynamic> initialFields;
  final Map<String, dynamic> customFields;
  final Set<String> protectedCustomFields;

  /// Fetches a protected field's plaintext value on demand, keyed by field
  /// name (e.g. `'Password'`, or a custom field's key). Some backends (the
  /// web/WASM implementation) omit protected values from [initialFields]/
  /// [customFields] entirely -- their plaintext only crosses the WASM/JS
  /// boundary once the user actually reveals a value, via this callback,
  /// rather than every time the entry is opened for editing. Null on the
  /// "Create Entry" flow, where there's nothing to fetch yet.
  final Future<String?> Function(String fieldKey)? fetchFieldValue;

  @override
  State<EntryFormDialog> createState() => _EntryFormDialogState();
}

class _EntryFormDialogState extends State<EntryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _urlController;
  late final TextEditingController _notesController;
  bool _passwordVisible = false;
  bool _passwordFetchAttempted = false;
  final Set<String> _visibleCustomFields = <String>{};
  final Map<String, String> _fetchedCustomFieldValues = <String, String>{};
  final Set<String> _customFieldFetchesAttempted = <String>{};

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
        text: widget.initialFields['Title'] as String? ?? '');
    _usernameController = TextEditingController(
      text: widget.initialFields['UserName'] as String? ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.initialFields['Password'] as String? ?? '',
    );
    _urlController = TextEditingController(
        text: widget.initialFields['URL'] as String? ?? '');
    _notesController = TextEditingController(
      text: widget.initialFields['Notes'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(
      EntryFormResult(
        title: _titleController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        url: _urlController.text.trim(),
        notes: _notesController.text,
      ),
    );
  }

  /// Reveals the password field, fetching its real value first if the
  /// backend scrubbed it from [EntryFormDialog.initialFields] (see
  /// [EntryFormDialog.fetchFieldValue]). Only fetches once, and only if the
  /// field is still exactly as it was populated at dialog-open time --
  /// otherwise a fetch after the user started typing a new password would
  /// clobber their edit.
  Future<void> _revealPassword() async {
    final fetch = widget.fetchFieldValue;
    if (!_passwordFetchAttempted &&
        fetch != null &&
        _passwordController.text.isEmpty) {
      _passwordFetchAttempted = true;
      final value = await fetch('Password');
      if (!mounted) return;
      if (value != null && _passwordController.text.isEmpty) {
        _passwordController.text = value;
      }
    }
    setState(() => _passwordVisible = true);
  }

  /// Mirrors [_revealPassword] for a protected custom field: fetches its
  /// real value on first reveal if the backend scrubbed it, otherwise just
  /// shows the value already present in [EntryFormDialog.customFields].
  Future<void> _revealCustomField(String key, String currentValue) async {
    final fetch = widget.fetchFieldValue;
    if (!_customFieldFetchesAttempted.contains(key) &&
        fetch != null &&
        currentValue.isEmpty) {
      _customFieldFetchesAttempted.add(key);
      final value = await fetch(key);
      if (!mounted) return;
      if (value != null) {
        _fetchedCustomFieldValues[key] = value;
      }
    }
    setState(() => _visibleCustomFields.add(key));
  }

  void _generatePassword() {
    const characters =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#%^&*()-_=+[]{}';
    final random = Random.secure();
    final value = List.generate(
      20,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
    setState(() {
      _passwordController.text = value;
      _passwordVisible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: Spacing.lg),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Title is required';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _passwordController,
              obscureText: !_passwordVisible,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: Wrap(
                  spacing: 0,
                  children: [
                    IconButton(
                      tooltip: 'Generate password',
                      onPressed: _generatePassword,
                      icon: const Icon(Icons.password_rounded),
                    ),
                    IconButton(
                      tooltip:
                          _passwordVisible ? 'Hide password' : 'Show password',
                      onPressed: () {
                        if (_passwordVisible) {
                          setState(() => _passwordVisible = false);
                        } else {
                          _revealPassword();
                        }
                      },
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                    ),
                  ],
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: 'URL'),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes'),
              minLines: 4,
              maxLines: 6,
            ),
            const SizedBox(height: Spacing.lg),
            Text('Custom fields', style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
            if (widget.customFields.isEmpty)
              Text(
                'No custom fields',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              )
            else
              ...widget.customFields.entries.map((entry) {
                final isProtected =
                    widget.protectedCustomFields.contains(entry.key);
                final isVisible =
                    !isProtected || _visibleCustomFields.contains(entry.key);
                final rawValue = entry.value.toString();
                final revealedValue =
                    _fetchedCustomFieldValues[entry.key] ?? rawValue;
                return Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.key, style: theme.textTheme.labelMedium),
                      const SizedBox(height: Spacing.xs),
                      if (isProtected)
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                // Some backends omit the plaintext of a
                                // protected value from `customFields`
                                // entirely (see `fetchFieldValue`), so the
                                // hidden mask can't be sized to the real
                                // value's length -- use a fixed width.
                                isVisible ? revealedValue : '••••••••',
                              ),
                            ),
                            IconButton(
                              tooltip: isVisible ? 'Hide value' : 'Show value',
                              onPressed: () {
                                if (isVisible) {
                                  setState(
                                    () =>
                                        _visibleCustomFields.remove(entry.key),
                                  );
                                } else {
                                  _revealCustomField(entry.key, rawValue);
                                }
                              },
                              icon: Icon(
                                isVisible
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                            ),
                          ],
                        )
                      else
                        SelectableText(rawValue),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: content,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.lg,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: Spacing.sm),
              FilledButton(
                onPressed: _submit,
                child: Text(widget.submitLabel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoveEntryDialog extends StatefulWidget {
  const _MoveEntryDialog({
    required this.options,
    this.initialGroupUuid,
  });

  final List<_GroupOption> options;
  final String? initialGroupUuid;

  @override
  State<_MoveEntryDialog> createState() => _MoveEntryDialogState();
}

class _MoveEntryDialogState extends State<_MoveEntryDialog> {
  String? _selectedUuid;

  @override
  void initState() {
    super.initState();
    _selectedUuid = widget.initialGroupUuid ??
        (widget.options.isEmpty ? null : widget.options.first.uuid);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Move Entry', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Spacing.lg),
          DropdownButtonFormField<String>(
            initialValue: _selectedUuid,
            decoration: const InputDecoration(labelText: 'Destination group'),
            items: widget.options
                .map(
                  (option) => DropdownMenuItem<String>(
                    value: option.uuid,
                    child: Text(option.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedUuid = value;
              });
            },
          ),
          const SizedBox(height: Spacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: Spacing.sm),
              FilledButton(
                onPressed: _selectedUuid == null
                    ? null
                    : () => Navigator.of(context).pop(_selectedUuid),
                child: const Text('Move Entry'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupOption {
  const _GroupOption({
    required this.uuid,
    required this.label,
  });

  final String uuid;
  final String label;
}

List<_GroupOption> _flattenGroups(
  List<VaultGroup> groups, {
  List<String> parents = const <String>[],
}) {
  final options = <_GroupOption>[];
  for (final group in groups) {
    final label = [...parents, group.name].join(' / ');
    options.add(_GroupOption(uuid: group.uuid, label: label));
    options.addAll(
      _flattenGroups(
        group.children,
        parents: [...parents, group.name],
      ),
    );
  }
  return options;
}
