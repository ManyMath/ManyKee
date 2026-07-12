import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:keepass_ui/keepass_ui.dart' show ClipboardManager, VaultEntry;
import 'package:manyui/manyui.dart';

import '../state/vault_state_provider.dart';

/// Full entry inspector with protected-field reveal, custom fields, tags,
/// and a live TOTP countdown when the database exposes one.
class EntryDetail extends HookConsumerWidget {
  const EntryDetail({
    required this.entry,
    required this.sessionIdentity,
    this.onEditEntry,
    this.onMoveEntry,
    this.onDeleteEntry,
    super.key,
  });

  final VaultEntry entry;
  final Object sessionIdentity;
  final VoidCallback? onEditEntry;
  final VoidCallback? onMoveEntry;
  final VoidCallback? onDeleteEntry;

  static const Set<String> _standardFields = <String>{
    'Title',
    'UserName',
    'Password',
    'URL',
    'Notes',
    'Tags',
    'protected',
    'custom_data',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MTheme.of(context);
    final vault = ref.watch(vaultStateProvider);
    final clipboard = useMemoized(ClipboardManager.new);
    final fields = useState<Map<String, dynamic>?>(null);
    final loadError = useState(false);
    final loadAttempt = useState(0);
    final totp = useState<Map<String, dynamic>?>(null);
    final revealedSecrets = useState(const <String, String>{});
    final loadingSecrets = useState(const <String>{});

    useEffect(() {
      var cancelled = false;
      Timer? timer;
      fields.value = null;
      loadError.value = false;
      totp.value = null;
      revealedSecrets.value = const <String, String>{};

      Future<void> refreshTotp() async {
        try {
          final value = await vault.getTotpCode(entry.uuid);
          if (!cancelled) totp.value = value;
        } catch (_) {
          if (!cancelled) totp.value = null;
        }
      }

      Future<void> load() async {
        try {
          final value = await vault.readEntryFields(entry.uuid);
          if (cancelled) return;
          fields.value = value;
          await refreshTotp();
          if (cancelled || totp.value == null) return;
          timer = Timer.periodic(const Duration(seconds: 1), (_) async {
            final current = totp.value;
            final remaining = (current?['valid_for'] as num?)?.toInt();
            if (remaining == null) return;
            if (remaining <= 1) {
              await refreshTotp();
            } else if (!cancelled) {
              totp.value = <String, dynamic>{
                ...current!,
                'valid_for': remaining - 1,
              };
            }
          });
        } catch (_) {
          if (!cancelled) loadError.value = true;
        }
      }

      unawaited(load());
      return () {
        cancelled = true;
        timer?.cancel();
      };
    }, <Object?>[sessionIdentity, entry.uuid, loadAttempt.value]);

    if (loadError.value) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: MAlert(
            variant: MAlertVariant.destructive,
            title: 'Entry could not be loaded',
            message:
                'The vault is still open. Retry this entry or select another one.',
            actions: <Widget>[
              MButton(
                variant: MButtonVariant.outline,
                onPressed: () => loadAttempt.value++,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    MIcon(MIconData.refresh, size: 15),
                    SizedBox(width: 7),
                    Text('Retry'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final loaded = fields.value;
    if (loaded == null) {
      return const Center(child: MLoadingState(message: 'Loading entry'));
    }

    final protected = _protectedFields(loaded['protected']);
    final loadedTitle = loaded['Title'] as String? ?? '';
    final titleProtected = protected['Title'] == true || entry.titleProtected;
    final title = titleProtected
        ? 'Protected entry'
        : loadedTitle.isEmpty
        ? entry.title
        : loadedTitle;
    final username = loaded['UserName'] as String? ?? entry.username;
    final url = loaded['URL'] as String? ?? entry.url;
    final notes = loaded['Notes'] as String? ?? '';
    final tags = _tags(loaded['Tags']);
    final customFields = _customFields(loaded);
    final hasPassword =
        loaded.containsKey('Password') || protected['Password'] == true;

    Future<void> copyValue(String? value) async {
      if (value == null || value.isEmpty) return;
      final copied = await clipboard.copyWithAutoClear(value);
      if (!context.mounted) return;
      showMToast(
        context,
        builder: (_) =>
            Text(copied ? clipboard.lastSuccessMessage : 'Copy failed'),
        duration: const Duration(seconds: 2),
      );
    }

    Future<String?> loadSecret(String fieldName) async {
      final revealed = revealedSecrets.value[fieldName];
      if (revealed != null) return revealed;
      final inlineValue = loaded[fieldName] as String?;
      if (inlineValue != null && inlineValue.isNotEmpty) return inlineValue;
      return vault.readEntryField(entry.uuid, fieldName);
    }

    void showSecretReadError(String fieldName) {
      if (!context.mounted) return;
      showMToast(
        context,
        builder: (_) => Text('$fieldName could not be read.'),
        duration: const Duration(seconds: 2),
      );
    }

    Future<void> toggleSecret(String fieldName) async {
      if (revealedSecrets.value.containsKey(fieldName)) {
        final next = Map<String, String>.of(revealedSecrets.value)
          ..remove(fieldName);
        revealedSecrets.value = next;
        return;
      }
      loadingSecrets.value = <String>{...loadingSecrets.value, fieldName};
      try {
        final value = await loadSecret(fieldName);
        if (context.mounted) {
          revealedSecrets.value = <String, String>{
            ...revealedSecrets.value,
            fieldName: value ?? '',
          };
        }
      } catch (_) {
        showSecretReadError(fieldName);
      } finally {
        if (context.mounted) {
          loadingSecrets.value = Set<String>.of(loadingSecrets.value)
            ..remove(fieldName);
        }
      }
    }

    Future<void> copySecret(String fieldName) async {
      try {
        await copyValue(await loadSecret(fieldName));
      } catch (_) {
        showSecretReadError(fieldName);
      }
    }

    final totpCode = totp.value?['code'] as String?;
    final totpRemaining = (totp.value?['valid_for'] as num?)?.toInt();
    final totpPeriod = (totp.value?['period'] as num?)?.toInt();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title.isEmpty ? '(untitled)' : title,
                    style: theme.typography.headlineSmall,
                  ),
                  if (entry.breadcrumb?.isNotEmpty == true) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      entry.breadcrumb!,
                      style: theme.typography.caption.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onEditEntry != null)
              MIconButton(
                icon: MIconData.edit,
                label: 'Edit entry',
                onPressed: onEditEntry,
              ),
            if (onMoveEntry != null)
              MIconButton(
                icon: MIconData.arrowRight,
                label: 'Move entry',
                onPressed: onMoveEntry,
              ),
            if (onDeleteEntry != null)
              MIconButton(
                icon: MIconData.trash,
                label: 'Delete entry',
                onPressed: onDeleteEntry,
              ),
          ],
        ),
        const SizedBox(height: 16),
        const MDivider(),
        const SizedBox(height: 18),
        if (titleProtected)
          _SecretField(
            label: 'Title',
            fieldName: 'Title',
            revealedValue: revealedSecrets.value['Title'],
            loading: loadingSecrets.value.contains('Title'),
            onToggle: () => toggleSecret('Title'),
            onCopy: () => copySecret('Title'),
          ),
        if (protected['UserName'] == true)
          _SecretField(
            label: 'Username',
            fieldName: 'UserName',
            revealedValue: revealedSecrets.value['UserName'],
            loading: loadingSecrets.value.contains('UserName'),
            onToggle: () => toggleSecret('UserName'),
            onCopy: () => copySecret('UserName'),
          )
        else if (username.isNotEmpty)
          _Field(
            label: 'Username',
            value: username,
            actions: <Widget>[
              _CopyButton(
                label: 'Copy username',
                onPressed: () => copyValue(username),
              ),
            ],
          ),
        if (hasPassword)
          _SecretField(
            label: 'Password',
            fieldName: 'Password',
            revealedValue: revealedSecrets.value['Password'],
            loading: loadingSecrets.value.contains('Password'),
            onToggle: () => toggleSecret('Password'),
            onCopy: () => copySecret('Password'),
          ),
        if (protected['URL'] == true)
          _SecretField(
            label: 'URL',
            fieldName: 'URL',
            revealedValue: revealedSecrets.value['URL'],
            loading: loadingSecrets.value.contains('URL'),
            onToggle: () => toggleSecret('URL'),
            onCopy: () => copySecret('URL'),
          )
        else if (url.isNotEmpty)
          _Field(
            label: 'URL',
            value: url,
            actions: <Widget>[
              _CopyButton(label: 'Copy URL', onPressed: () => copyValue(url)),
            ],
          ),
        if (protected['Notes'] == true)
          _SecretField(
            label: 'Notes',
            fieldName: 'Notes',
            revealedValue: revealedSecrets.value['Notes'],
            loading: loadingSecrets.value.contains('Notes'),
            onToggle: () => toggleSecret('Notes'),
            onCopy: () => copySecret('Notes'),
          )
        else if (notes.isNotEmpty)
          _Field(label: 'Notes', value: notes, multiline: true),
        if (totpCode != null)
          _Field(
            label: 'One-time code',
            value: _formatTotpCode(totpCode),
            monospace: true,
            description: totpRemaining == null
                ? null
                : totpPeriod == null
                ? 'Refreshes in ${totpRemaining}s'
                : 'Refreshes in ${totpRemaining}s of ${totpPeriod}s',
            actions: <Widget>[
              _CopyButton(
                label: 'Copy one-time code',
                onPressed: () => copyValue(totpCode),
              ),
            ],
          ),
        for (final custom in customFields.entries)
          if (protected[custom.key] == true)
            _SecretField(
              label: custom.key,
              fieldName: custom.key,
              revealedValue: revealedSecrets.value[custom.key],
              loading: loadingSecrets.value.contains(custom.key),
              onToggle: () => toggleSecret(custom.key),
              onCopy: () => copySecret(custom.key),
            )
          else
            _Field(
              label: custom.key,
              value: custom.value,
              actions: <Widget>[
                _CopyButton(
                  label: 'Copy ${custom.key}',
                  onPressed: () => copyValue(custom.value),
                ),
              ],
            ),
        if (tags.isNotEmpty) ...<Widget>[
          Text(
            'Tags',
            style: theme.typography.caption.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: tags
                .map(
                  (tag) => MBadge(
                    variant: MBadgeVariant.secondary,
                    child: Text(tag),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  Map<String, bool> _protectedFields(dynamic raw) {
    if (raw is! Map) return const <String, bool>{};
    return raw.map(
      (key, value) => MapEntry<String, bool>(key.toString(), value == true),
    );
  }

  List<String> _tags(dynamic raw) {
    if (raw is String) {
      return raw
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is List) {
      return raw.map((tag) => tag.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  Map<String, String> _customFields(Map<String, dynamic> fields) {
    final custom = <String, String>{};
    final rawCustom = fields['custom_data'];
    if (rawCustom is Map) {
      for (final entry in rawCustom.entries) {
        if (entry.key.toString().toLowerCase() == 'otp') continue;
        custom[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }
    for (final entry in fields.entries) {
      if (_standardFields.contains(entry.key)) continue;
      custom[entry.key] = entry.value?.toString() ?? '';
    }
    return custom;
  }

  String _formatTotpCode(String code) =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
}

class _SecretField extends StatelessWidget {
  const _SecretField({
    required this.label,
    required this.fieldName,
    required this.revealedValue,
    required this.loading,
    required this.onToggle,
    required this.onCopy,
  });

  final String label;
  final String fieldName;
  final String? revealedValue;
  final bool loading;
  final VoidCallback onToggle;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _Field(
      label: label,
      value: revealedValue ?? '••••••••',
      monospace: revealedValue != null,
      actions: <Widget>[
        MIconButton(
          icon: revealedValue == null ? MIconData.eye : MIconData.eyeOff,
          label: revealedValue == null
              ? 'Reveal $fieldName'
              : 'Hide $fieldName',
          size: MButtonSize.sm,
          onPressed: loading ? null : onToggle,
        ),
        _CopyButton(label: 'Copy $fieldName', onPressed: onCopy),
      ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => MIconButton(
    icon: MIconData.copy,
    label: label,
    size: MButtonSize.sm,
    onPressed: onPressed,
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.description,
    this.actions = const <Widget>[],
    this.monospace = false,
    this.multiline = false,
  });

  final String label;
  final String value;
  final String? description;
  final List<Widget> actions;
  final bool monospace;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    if (value.isEmpty && actions.isEmpty) return const SizedBox.shrink();
    return MPropertyRow(
      padding: const EdgeInsets.only(bottom: 18),
      label: label,
      description: description,
      value: Text(
        value,
        style: monospace ? theme.typography.code : theme.typography.body,
        maxLines: multiline ? null : 2,
        overflow: multiline ? null : TextOverflow.ellipsis,
      ),
      trailing: actions.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
    );
  }
}
