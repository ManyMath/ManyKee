import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:keepass_ui/keepass_ui.dart' show ClipboardManager, VaultEntry;
import 'package:manyui/manyui.dart';

import '../state/vault_state_provider.dart';

/// Read-only detail view for one entry: title, username, password (hidden
/// until revealed, fetched on demand), URL, and notes, with copy buttons.
class EntryDetail extends HookConsumerWidget {
  const EntryDetail({required this.entry, super.key});

  final VaultEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MTheme.of(context);
    final vault = ref.watch(vaultStateProvider);

    final fields = useState<Map<String, dynamic>?>(null);
    final revealedPassword = useState<String?>(null);

    useEffect(() {
      fields.value = null;
      revealedPassword.value = null;
      var cancelled = false;
      vault.readEntryFields(entry.uuid).then((value) {
        if (!cancelled) fields.value = value;
      }).catchError((Object _) {
        if (!cancelled) fields.value = const <String, dynamic>{};
      });
      return () => cancelled = true;
    }, <Object?>[entry.uuid]);

    final loaded = fields.value;
    if (loaded == null) {
      return const Center(child: MCircularProgress.indeterminate());
    }

    final title = loaded['Title'] as String? ?? entry.title;
    final username = loaded['UserName'] as String? ?? entry.username;
    final url = loaded['URL'] as String? ?? entry.url;
    final notes = loaded['Notes'] as String? ?? '';

    Future<void> copyField(String label, String? value) async {
      if (value == null || value.isEmpty) return;
      final manager = ClipboardManager();
      final ok = await manager.copyWithAutoClear(value);
      if (!context.mounted) return;
      showMToast(
        context,
        builder: (_) =>
            Text(ok ? '$label copied' : 'Copy failed'),
        duration: const Duration(seconds: 2),
      );
    }

    Future<void> copyPassword() async {
      final password =
          revealedPassword.value ??
              await vault.readEntryField(entry.uuid, 'Password');
      if (!context.mounted) return;
      await copyField('Password', password);
    }

    Future<void> toggleReveal() async {
      if (revealedPassword.value != null) {
        revealedPassword.value = null;
        return;
      }
      final password = await vault.readEntryField(entry.uuid, 'Password');
      revealedPassword.value = password ?? '';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          title.isEmpty ? '(untitled)' : title,
          style: theme.typography.headlineSmall,
        ),
        const SizedBox(height: 16),
        _Field(
          label: 'Username',
          value: username,
          onCopy: () => copyField('Username', username),
        ),
        _Field(
          label: 'Password',
          value: revealedPassword.value ?? '••••••••',
          monospace: revealedPassword.value != null,
          onCopy: copyPassword,
          trailing: MButton(
            variant: MButtonVariant.ghost,
            size: MButtonSize.sm,
            onPressed: toggleReveal,
            child: Text(revealedPassword.value == null ? 'Reveal' : 'Hide'),
          ),
        ),
        _Field(
          label: 'URL',
          value: url,
          onCopy: () => copyField('URL', url),
        ),
        _Field(
          label: 'Notes',
          value: notes,
          multiline: true,
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.onCopy,
    this.trailing,
    this.monospace = false,
    this.multiline = false,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;
  final Widget? trailing;
  final bool monospace;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    if (value.isEmpty && trailing == null) {
      return const SizedBox.shrink();
    }

    final valueStyle = monospace ? theme.typography.code : theme.typography.body;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MLabel(label),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: multiline
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  value,
                  style: valueStyle,
                  maxLines: multiline ? null : 1,
                  overflow: multiline ? null : TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
              if (onCopy != null) ...[
                const SizedBox(width: 8),
                MButton(
                  variant: MButtonVariant.ghost,
                  size: MButtonSize.sm,
                  onPressed: onCopy,
                  child: const Text('Copy'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
