import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';

import '../settings/settings_page.dart';
import '../state/recent_database.dart';
import '../state/settings_state.dart';
import '../state/unlock_error_mapper.dart';
import '../state/vault_state_provider.dart';
import '../theme.dart';

/// Landing page: open a .kdbx database and unlock it.
///
/// Two modes: when the vault remembers a previously opened file
/// (locked, `lastFilePath` set) it shows a quick re-unlock view; otherwise
/// the full choose-file + password form.
class UnlockPage extends HookConsumerWidget {
  const UnlockPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MTheme.of(context);
    final vault = ref.watch(vaultStateProvider);

    return MScaffold(
      header: Row(
        children: <Widget>[
          Text('ManyKee', style: theme.typography.title),
          const Spacer(),
          MButton(
            variant: MButtonVariant.ghost,
            onPressed: () => showSettingsPage(context),
            child: const Text('Settings'),
          ),
          const SizedBox(width: 8),
          MButton(
            variant: MButtonVariant.ghost,
            onPressed: () => ref
                .read(manyKeeSettingsControllerProvider)
                .toggleLightDarkTheme(),
            semanticLabel: 'Toggle theme',
            child: MIcon(
              ref.watch(themeModeProvider) == MThemeMode.dark
                  ? MIconData.sun
                  : MIconData.moon,
            ),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: MCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: vault.lastFilePath != null
                    ? const _ReUnlockForm()
                    : const _UnlockForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full unlock form: pick a database, optional key file, master password.
class _UnlockForm extends HookConsumerWidget {
  const _UnlockForm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MTheme.of(context);
    final recents = ref.watch(recentDatabasesProvider);

    final filePath = useState<String?>(null);
    final databaseBytes = useState<Uint8List?>(null);
    final filename = useState<String?>(null);
    final keyFilePath = useState<String?>(null);
    final keyFileBytes = useState<Uint8List?>(null);
    final keyFilename = useState<String?>(null);
    final password = useState('');
    final unlocking = useState(false);
    final creating = useState(false);
    final passwordController = _usePasswordController();
    final yubiKeyAttempt = useState(0);
    final yubiKeys = _useYubiKeys(ref, yubiKeyAttempt.value);
    final useYubiKey = useState(false);

    final busy = unlocking.value || creating.value;
    final canUnlock =
        filePath.value != null && password.value.isNotEmpty && !busy;

    void selectRecent(RecentDatabase recent) {
      filePath.value = recent.path;
      databaseBytes.value = null;
      filename.value = recent.label;
    }

    Future<void> pickDatabase() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['kdbx'],
        dialogTitle: 'Choose KDBX File',
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        filePath.value = file.path ?? file.name;
        databaseBytes.value = file.bytes;
        filename.value = file.name;
      }
    }

    Future<void> pickKeyFile() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['key', 'keyx', 'xml'],
        dialogTitle: 'Choose Key File',
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        keyFilePath.value = file.path;
        keyFileBytes.value = file.bytes;
        keyFilename.value = file.name;
      }
    }

    Future<void> unlock() async {
      if (!canUnlock) return;
      await _runUnlock(
        context: context,
        ref: ref,
        unlocking: unlocking,
        password: password,
        passwordController: passwordController,
        filePath: filePath.value!,
        dbBytes: databaseBytes.value,
        keyFilePath: keyFilePath.value,
        keyFileBytes: keyFileBytes.value,
        filename: filename.value,
        yubiKeySlot: useYubiKey.value && (yubiKeys.value?.isNotEmpty ?? false)
            ? '2'
            : null,
      );
    }

    Future<void> createDatabase() async {
      if (busy) return;
      final request = await _showCreateDatabaseDialog(context);
      if (request == null) return;

      final vault = ref.read(vaultStateProvider);
      final String? selectedPath;
      try {
        selectedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Create KDBX File',
          fileName: 'NewDatabase.kdbx',
          type: FileType.custom,
          allowedExtensions: const <String>['kdbx'],
        );
      } catch (e) {
        vault.setErrorWithDetail(
          'CREATE_DATABASE_FAILED',
          'Could not create the database. Please try again.',
          detail: truncateErrorDetail(e.toString()),
        );
        return;
      }
      if (selectedPath == null) return;

      final databasePath = _ensureKdbxExtension(selectedPath);
      final databaseName = _filenameForPath(databasePath);
      creating.value = true;
      try {
        await vault.createDatabaseAtPath(
          filePath: databasePath,
          password: request.password,
          filename: databaseName,
        );
      } on UnimplementedError catch (e) {
        vault.setError(
          'UNSUPPORTED',
          e.message ?? 'Database creation is not supported on this platform.',
        );
      } catch (e) {
        vault.setErrorWithDetail(
          'CREATE_DATABASE_FAILED',
          'Could not create the database. Please try again.',
          detail: truncateErrorDetail(e.toString()),
        );
      }
      if (vault.errorCode == null && !vault.isLocked) {
        ref
            .read(recentDatabasesControllerProvider)
            .recordOpened(databasePath, databaseName);
      }
      if (!context.mounted) return;
      creating.value = false;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Unlock a database', style: theme.typography.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Open a KeePass (.kdbx) file to get started.',
          style: theme.typography.bodySmall.copyWith(
            color: theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: 16),
        MButton(
          variant: MButtonVariant.outline,
          onPressed: busy ? null : createDatabase,
          child: Text(creating.value ? 'Creating…' : 'Create new database…'),
        ),
        if (recents.isNotEmpty) ...[
          const SizedBox(height: 24),
          const MLabel('Recent'),
          const SizedBox(height: 8),
          _RecentDatabasesList(
            recents: recents,
            enabled: !busy,
            onSelect: selectRecent,
          ),
        ],
        const SizedBox(height: 24),
        const MLabel('Database'),
        const SizedBox(height: 8),
        MButton(
          variant: MButtonVariant.outline,
          onPressed: busy ? null : pickDatabase,
          child: Text(
            filename.value ?? 'Choose file…',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 16),
        const MLabel('Key file (optional)'),
        const SizedBox(height: 8),
        MButton(
          variant: MButtonVariant.outline,
          onPressed: busy ? null : pickKeyFile,
          child: Text(
            keyFilename.value ?? 'Choose key file…',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 16),
        const MLabel('Master password'),
        const SizedBox(height: 8),
        MTextField(
          controller: passwordController,
          obscureText: true,
          placeholder: 'Password',
          semanticLabel: 'Master password',
          enabled: !busy,
          onChanged: (value) => password.value = value,
          onSubmitted: (_) => unlock(),
        ),
        _YubiKeyOption(
          yubiKeys: yubiKeys.value,
          useYubiKey: useYubiKey,
          enabled: !busy,
          onRedetect: () {
            yubiKeys.value = null;
            yubiKeyAttempt.value++;
          },
        ),
        _UnlockStatus(
          unlocking: unlocking.value,
          usingYubiKey:
              useYubiKey.value && (yubiKeys.value?.isNotEmpty ?? false),
        ),
        const SizedBox(height: 24),
        MButton(
          onPressed: canUnlock ? unlock : null,
          child: Text(unlocking.value ? 'Unlocking…' : 'Unlock'),
        ),
      ],
    );
  }
}

class _CreateDatabaseRequest {
  const _CreateDatabaseRequest({required this.password});

  final String password;
}

Future<_CreateDatabaseRequest?> _showCreateDatabaseDialog(
  BuildContext context,
) {
  return showMDialog<_CreateDatabaseRequest>(
    context,
    semanticLabel: 'Create new database',
    builder: (BuildContext ctx) => const _CreateDatabaseDialogContent(),
  );
}

class _CreateDatabaseDialogContent extends HookWidget {
  const _CreateDatabaseDialogContent();

  @override
  Widget build(BuildContext context) {
    final theme = MTheme.of(context);
    final password = useState('');
    final confirm = useState('');
    final mismatch =
        confirm.value.isNotEmpty && confirm.value != password.value;
    final canCreate =
        password.value.isNotEmpty && confirm.value == password.value;

    void submit() {
      if (!canCreate) return;
      Navigator.of(
        context,
      ).pop(_CreateDatabaseRequest(password: password.value));
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Create database', style: theme.typography.headlineSmall),
          const SizedBox(height: 16),
          const MLabel('Master password'),
          const SizedBox(height: 4),
          MTextField(
            obscureText: true,
            placeholder: 'Password',
            semanticLabel: 'New database master password',
            autofocus: true,
            onChanged: (value) => password.value = value,
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 12),
          const MLabel('Confirm password'),
          const SizedBox(height: 4),
          MTextField(
            obscureText: true,
            placeholder: 'Password',
            semanticLabel: 'Confirm new database master password',
            error: mismatch,
            errorText: mismatch ? 'Passwords do not match.' : null,
            onChanged: (value) => confirm.value = value,
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              MButton(
                variant: MButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              MButton(
                onPressed: canCreate ? submit : null,
                child: const Text('Create'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Quick re-unlock form shown when the vault was locked but the database
/// path is still known: password only, plus an escape hatch to open another
/// database.
class _ReUnlockForm extends HookConsumerWidget {
  const _ReUnlockForm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MTheme.of(context);
    final vault = ref.watch(vaultStateProvider);

    final password = useState('');
    final unlocking = useState(false);
    final passwordController = _usePasswordController();

    final filePath = vault.lastFilePath!;
    final canUnlock = password.value.isNotEmpty && !unlocking.value;

    Future<void> unlock() async {
      if (!canUnlock) return;
      await _runUnlock(
        context: context,
        ref: ref,
        unlocking: unlocking,
        password: password,
        passwordController: passwordController,
        filePath: filePath,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Vault locked', style: theme.typography.headlineSmall),
        const SizedBox(height: 8),
        Text(
          filePath,
          style: theme.typography.bodySmall.copyWith(
            color: theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: 24),
        const MLabel('Master password'),
        const SizedBox(height: 8),
        MTextField(
          controller: passwordController,
          obscureText: true,
          placeholder: 'Password',
          semanticLabel: 'Master password',
          enabled: !unlocking.value,
          autofocus: true,
          onChanged: (value) => password.value = value,
          onSubmitted: (_) => unlock(),
        ),
        _UnlockStatus(
          unlocking: unlocking.value,
          usingYubiKey: vault.lastYubiKeySlot != null,
        ),
        const SizedBox(height: 24),
        MButton(
          onPressed: canUnlock ? unlock : null,
          child: Text(unlocking.value ? 'Unlocking…' : 'Unlock'),
        ),
        const SizedBox(height: 8),
        MButton(
          variant: MButtonVariant.ghost,
          onPressed: unlocking.value ? null : vault.openDifferentFile,
          child: const Text('Open different database'),
        ),
      ],
    );
  }
}

/// Error message and in-flight progress, shared by both forms.
class _UnlockStatus extends ConsumerWidget {
  const _UnlockStatus({required this.unlocking, this.usingYubiKey = false});

  final bool unlocking;
  final bool usingYubiKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = MTheme.of(context);
    final vault = ref.watch(vaultStateProvider);
    final errorMessage = vault.errorMessage;
    final errorDetail = vault.errorDetail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (errorMessage != null && !unlocking) ...[
          const SizedBox(height: 12),
          Text(
            errorMessage,
            style: theme.typography.bodySmall.copyWith(
              color: theme.colors.destructive,
            ),
          ),
          if (errorDetail != null) ...[
            const SizedBox(height: 4),
            Text(
              errorDetail,
              style: theme.typography.caption.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
        ],
        if (unlocking) ...[
          const SizedBox(height: 16),
          const MProgress.indeterminate(semanticLabel: 'Unlocking'),
          const SizedBox(height: 8),
          StreamBuilder<int>(
            stream: vault.progress,
            builder: (context, snapshot) {
              final percent = snapshot.data;
              final label = percent == null
                  ? (usingYubiKey ? 'Touch your YubiKey…' : 'Deriving key…')
                  : 'Deriving key… $percent%';
              return Text(
                label,
                style: theme.typography.caption.copyWith(
                  color: theme.colors.mutedForeground,
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Detects connected YubiKeys. Holds null while detection runs, then the
/// (possibly empty) descriptor list. Detection re-runs whenever [attempt]
/// changes; the Re-detect button resets the notifier to null and bumps it.
ValueNotifier<List<Map<String, dynamic>>?> _useYubiKeys(
  WidgetRef ref,
  int attempt,
) {
  final yubiKeys = useState<List<Map<String, dynamic>>?>(null);
  useEffect(() {
    var cancelled = false;
    ref.read(vaultStateProvider).listYubiKeys().then((keys) {
      if (!cancelled) yubiKeys.value = keys;
    });
    return () => cancelled = true;
  }, <Object?>[attempt]);
  return yubiKeys;
}

/// YubiKey affordance under the password field: detection progress, a
/// "no key" caption with a Re-detect action, or the challenge-response
/// checkbox (HMAC slot 2) once a key is found. Hidden entirely on web,
/// where [ManyKeeVaultState.listYubiKeys] always returns an empty list.
class _YubiKeyOption extends StatelessWidget {
  const _YubiKeyOption({
    required this.yubiKeys,
    required this.useYubiKey,
    required this.enabled,
    required this.onRedetect,
  });

  final List<Map<String, dynamic>>? yubiKeys;
  final ValueNotifier<bool> useYubiKey;
  final bool enabled;
  final VoidCallback onRedetect;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final theme = MTheme.of(context);
    final captionStyle = theme.typography.caption.copyWith(
      color: theme.colors.mutedForeground,
    );
    final keys = yubiKeys;
    if (keys == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text('Detecting YubiKeys…', style: captionStyle),
      );
    }
    if (keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: <Widget>[
            Expanded(child: Text('No YubiKey detected.', style: captionStyle)),
            const SizedBox(width: 8),
            MButton(
              variant: MButtonVariant.ghost,
              size: MButtonSize.sm,
              onPressed: enabled ? onRedetect : null,
              child: const Text('Re-detect'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              MCheckbox(
                initialValue: useYubiKey.value,
                enabled: enabled,
                semanticLabel: 'Use YubiKey challenge-response',
                onChanged: (checked) => useYubiKey.value = checked,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  keys.length == 1
                      ? 'Use YubiKey (challenge-response, slot 2)'
                      : 'Use YubiKey (${keys.length} detected, slot 2)',
                  style: theme.typography.bodySmall,
                ),
              ),
            ],
          ),
          if (useYubiKey.value) ...[
            const SizedBox(height: 4),
            Text(
              'You may need to touch the key during unlock.',
              style: captionStyle,
            ),
          ],
        ],
      ),
    );
  }
}

/// List of previously-opened databases with a forget action, shown above the
/// file picker so re-opening a known database skips re-browsing entirely.
class _RecentDatabasesList extends ConsumerWidget {
  const _RecentDatabasesList({
    required this.recents,
    required this.enabled,
    required this.onSelect,
  });

  final List<RecentDatabase> recents;
  final bool enabled;
  final ValueChanged<RecentDatabase> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final recent in recents)
            MListTile(
              title: Text(recent.label, overflow: TextOverflow.ellipsis),
              subtitle: Text(recent.path, overflow: TextOverflow.ellipsis),
              semanticLabel: recent.label,
              onTap: enabled ? () => onSelect(recent) : null,
              trailing: MButton(
                variant: MButtonVariant.ghost,
                size: MButtonSize.sm,
                semanticLabel: 'Forget ${recent.label}',
                onPressed: enabled
                    ? () => ref
                          .read(recentDatabasesControllerProvider)
                          .forget(recent.path)
                    : null,
                child: const Text('Forget'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Owns a disposed-with-the-widget [MController] for the password field so
/// the form can clear it after a wrong-password attempt.
MController<String> _usePasswordController() {
  final controller = useMemoized(() => MController<String>(''));
  useEffect(() => controller.dispose, <Object?>[controller]);
  return controller;
}

String _ensureKdbxExtension(String path) =>
    path.toLowerCase().endsWith('.kdbx') ? path : '$path.kdbx';

String _filenameForPath(String path) {
  final parts = path.split(RegExp(r'[/\\]'));
  return parts.isEmpty || parts.last.isEmpty ? path : parts.last;
}

/// Runs an unlock attempt against the vault state, keeping the transient UI
/// state (spinner, password clearing) consistent across both forms.
Future<void> _runUnlock({
  required BuildContext context,
  required WidgetRef ref,
  required ValueNotifier<bool> unlocking,
  required ValueNotifier<String> password,
  required MController<String> passwordController,
  required String filePath,
  String? keyFilePath,
  Uint8List? dbBytes,
  Uint8List? keyFileBytes,
  String? filename,
  String? yubiKeySlot,
}) async {
  final vault = ref.read(vaultStateProvider);
  unlocking.value = true;
  try {
    if (dbBytes != null) {
      await vault.unlock(
        dbBytes: dbBytes,
        filePath: filePath,
        password: passwordController.value,
        keyFileBytes: keyFileBytes,
        filename: filename,
      );
    } else {
      await vault.unlockFromPath(
        filePath: filePath,
        password: passwordController.value,
        keyFilePath: keyFilePath,
        filename: filename,
        yubiKeySlot: yubiKeySlot,
      );
    }
  } on UnimplementedError catch (e) {
    vault.setError(
      'UNSUPPORTED',
      e.message ?? 'Unlocking is not supported on this platform yet.',
    );
  } catch (e) {
    vault.setErrorWithDetail(
      'UNKNOWN',
      'Something went wrong while unlocking. Please try again.',
      detail: truncateErrorDetail(e.toString()),
    );
  }
  if (!context.mounted) return;
  unlocking.value = false;
  if (vault.errorCode == 'WRONG_PASSWORD') {
    passwordController.value = '';
    password.value = '';
  }
  if (vault.errorCode == null) {
    if (!kIsWeb) {
      ref
          .read(recentDatabasesControllerProvider)
          .recordOpened(filePath, filename ?? vault.lastFilename ?? filePath);
    }
  }
}
