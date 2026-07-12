import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';
import 'package:manyui_hooks/manyui_hooks.dart';
import 'package:manyui_riverpod/manyui_riverpod.dart';

import '../settings/settings_page.dart';
import '../state/recent_database.dart';
import '../state/security_scoped_file_access.dart';
import '../state/settings_state.dart';
import '../state/unlock_error_mapper.dart';
import '../state/vault_state_provider.dart';
import '../state/vault_sessions.dart';
import '../theme.dart';
import '../vault/vault_sessions_dialog.dart';

/// Landing page: open a .kdbx database and unlock it.
///
/// Two modes: when the vault remembers a previously opened file
/// (locked, `lastFilePath` set) it shows a quick re-unlock view; otherwise
/// the full choose-file + password form.
class UnlockPage extends HookConsumerWidget {
  const UnlockPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultStateProvider);
    final sessions = ref.watch(vaultSessionsControllerProvider);
    final showSessions =
        sessions != null &&
        (sessions.sessionCount > 1 || sessions.hasUnlockedSessions);

    return MScaffold(
      header: MAppHeader(
        title: 'ManyKee',
        actions: <Widget>[
          if (showSessions)
            MButton(
              variant: MButtonVariant.ghost,
              onPressed: () => showVaultSessionsDialog(context, sessions),
              child: const Text('Databases'),
            ),
          MIconButton(
            icon: MIconData.settings,
            label: 'Settings',
            onPressed: () => showSettingsPage(context),
          ),
          MIconButton(
            icon: ref.watchMThemeMode(themeModeProvider) == MThemeMode.dark
                ? MIconData.sun
                : MIconData.moon,
            label: 'Toggle theme',
            onPressed: () => ref
                .read(manyKeeSettingsControllerProvider)
                .toggleLightDarkTheme(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
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
    final recents = ref.watch(recentDatabasesProvider);
    final vault = ref.watch(vaultStateProvider);

    final filePath = useState<String?>(null);
    final databaseBytes = useState<Uint8List?>(null);
    final filename = useState<String?>(null);
    final securityScopedBookmark = useState<String?>(null);
    final keyFilePath = useState<String?>(null);
    final keyFileBytes = useState<Uint8List?>(null);
    final keyFilename = useState<String?>(null);
    final unlocking = useState(false);
    final creating = useState(false);
    final passwordController = _usePasswordController();
    final passwordValue = useMControllerValue(passwordController);
    final databaseFocus = useFocusNode();
    final keyFileFocus = useFocusNode();
    final passwordFocus = useFocusNode();
    final yubiKeyAttempt = useState(0);
    final yubiKeys = _useYubiKeys(ref, yubiKeyAttempt.value);
    final useYubiKey = useState(false);

    final busy = unlocking.value || creating.value;
    final canUnlock =
        filePath.value != null && passwordValue.isNotEmpty && !busy;

    void selectRecent(RecentDatabase recent) {
      filePath.value = recent.path;
      databaseBytes.value = null;
      filename.value = recent.label;
      securityScopedBookmark.value = recent.securityScopedBookmark;
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
        final selectedPath = file.path ?? file.name;
        filePath.value = selectedPath;
        databaseBytes.value = file.bytes;
        filename.value = file.name;
        securityScopedBookmark.value = file.path == null
            ? null
            : await ref
                  .read(securityScopedFileAccessProvider)
                  .bookmarkForPath(file.path!);
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
        passwordController: passwordController,
        filePath: filePath.value!,
        securityScopedBookmark: securityScopedBookmark.value,
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
        final bookmark = await ref
            .read(securityScopedFileAccessProvider)
            .bookmarkForPath(databasePath);
        ref
            .read(recentDatabasesControllerProvider)
            .recordOpened(
              databasePath,
              databaseName,
              securityScopedBookmark: bookmark,
            );
      }
      if (!context.mounted) return;
      creating.value = false;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const MSectionHeader(
          title: 'Unlock a database',
          description: 'Open a KeePass (.kdbx) file to get started.',
        ),
        const SizedBox(height: 16),
        if (vault.supportsDatabaseCreation)
          MButton(
            variant: MButtonVariant.outline,
            onPressed: busy ? null : createDatabase,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const MIcon(MIconData.plus, size: 16),
                const SizedBox(width: 8),
                Text(creating.value ? 'Creating…' : 'Create new database…'),
              ],
            ),
          ),
        if (recents.isNotEmpty) ...[
          const SizedBox(height: 24),
          MField(
            label: 'Recent',
            enabled: !busy,
            child: _RecentDatabasesList(
              recents: recents,
              selectedPath: filePath.value,
              enabled: !busy,
              onSelect: selectRecent,
            ),
          ),
        ],
        const SizedBox(height: 24),
        MField(
          label: 'Database',
          focusNode: databaseFocus,
          enabled: !busy,
          child: MButton(
            focusNode: databaseFocus,
            variant: MButtonVariant.outline,
            onPressed: busy ? null : pickDatabase,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const MIcon(MIconData.folder, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    filename.value ?? 'Choose file…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        MField(
          label: 'Key file (optional)',
          focusNode: keyFileFocus,
          enabled: !busy,
          child: MButton(
            focusNode: keyFileFocus,
            variant: MButtonVariant.outline,
            onPressed: busy ? null : pickKeyFile,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const MIcon(MIconData.folder, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    keyFilename.value ?? 'Choose key file…',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        MField(
          label: 'Master password',
          focusNode: passwordFocus,
          enabled: !busy,
          child: MSecretField(
            focusNode: passwordFocus,
            controller: passwordController,
            placeholder: 'Password',
            semanticLabel: 'Master password',
            enabled: !busy,
            onSubmitted: (_) => unlock(),
          ),
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
    final password = useState('');
    final confirm = useState('');
    final passwordFocus = useFocusNode();
    final confirmFocus = useFocusNode();
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

    return MDialogContent(
      title: 'Create database',
      maxWidth: 380,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          MField(
            label: 'Master password',
            focusNode: passwordFocus,
            spacing: 4,
            child: MSecretField(
              focusNode: passwordFocus,
              placeholder: 'Password',
              semanticLabel: 'New database master password',
              autofocus: true,
              onChanged: (value) => password.value = value,
              onSubmitted: (_) => submit(),
            ),
          ),
          const SizedBox(height: 12),
          MField(
            label: 'Confirm password',
            focusNode: confirmFocus,
            spacing: 4,
            errorText: mismatch ? 'Passwords do not match.' : null,
            child: MSecretField(
              focusNode: confirmFocus,
              placeholder: 'Password',
              semanticLabel: 'Confirm new database master password',
              error: mismatch,
              onChanged: (value) => confirm.value = value,
              onSubmitted: (_) => submit(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        MButton(
          variant: MButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        MButton(
          onPressed: canCreate ? submit : null,
          child: const Text('Create'),
        ),
      ],
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
    final vault = ref.watch(vaultStateProvider);

    final unlocking = useState(false);
    final passwordController = _usePasswordController();
    final passwordValue = useMControllerValue(passwordController);
    final passwordFocus = useFocusNode();

    final filePath = vault.lastFilePath!;
    final canUnlock = passwordValue.isNotEmpty && !unlocking.value;

    Future<void> unlock() async {
      if (!canUnlock) return;
      await _runUnlock(
        context: context,
        ref: ref,
        unlocking: unlocking,
        passwordController: passwordController,
        filePath: filePath,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        MSectionHeader(
          title: 'Vault locked',
          description: _filenameForPath(filePath),
        ),
        const SizedBox(height: 12),
        MInsetPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              const MIcon(MIconData.lock, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(filePath, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        MField(
          label: 'Master password',
          focusNode: passwordFocus,
          enabled: !unlocking.value,
          child: MSecretField(
            focusNode: passwordFocus,
            controller: passwordController,
            placeholder: 'Password',
            semanticLabel: 'Master password',
            enabled: !unlocking.value,
            autofocus: true,
            onSubmitted: (_) => unlock(),
          ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (errorMessage != null && !unlocking) ...[
          const SizedBox(height: 12),
          MAlert(variant: MAlertVariant.destructive, message: errorMessage),
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
    required this.selectedPath,
    required this.enabled,
    required this.onSelect,
  });

  final List<RecentDatabase> recents;
  final String? selectedPath;
  final bool enabled;
  final ValueChanged<RecentDatabase> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MInsetPanel(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final recent in recents)
            MListTile(
              title: Text(recent.label, overflow: TextOverflow.ellipsis),
              subtitle: Text(recent.path, overflow: TextOverflow.ellipsis),
              leading: const MIcon(MIconData.folder, size: 16),
              selected: recent.path == selectedPath,
              semanticLabel: recent.label,
              onTap: enabled ? () => onSelect(recent) : null,
              trailing: MIconButton(
                icon: MIconData.trash,
                label: 'Forget ${recent.label}',
                size: MButtonSize.sm,
                onPressed: enabled
                    ? () => ref
                          .read(recentDatabasesControllerProvider)
                          .forget(recent.path)
                    : null,
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
  return useMController<String>('');
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
  required MController<String> passwordController,
  required String filePath,
  String? keyFilePath,
  String? securityScopedBookmark,
  Uint8List? dbBytes,
  Uint8List? keyFileBytes,
  String? filename,
  String? yubiKeySlot,
}) async {
  final vault = ref.read(vaultStateProvider);
  final recentDatabases = ref.read(recentDatabasesControllerProvider);
  unlocking.value = true;
  SecurityScopedAccess? securityScopedAccess;
  var retainedAccess = false;
  var effectiveFilePath = filePath;
  final fileAccess = ref.read(securityScopedFileAccessProvider);
  try {
    securityScopedAccess = await fileAccess.startFromBookmark(
      securityScopedBookmark,
    );
    if (fileAccess.isSupported &&
        securityScopedBookmark != null &&
        securityScopedBookmark.isNotEmpty &&
        securityScopedAccess == null) {
      vault.setErrorWithDetail(
        'FILE_ACCESS_EXPIRED',
        'ManyKee no longer has permission to open this file.',
        detail: 'Choose the database file again to refresh macOS file access.',
      );
      return;
    }
    effectiveFilePath = securityScopedAccess?.path ?? filePath;
    if (dbBytes != null) {
      await vault.unlock(
        dbBytes: dbBytes,
        filePath: effectiveFilePath,
        password: passwordController.value,
        keyFileBytes: keyFileBytes,
        filename: filename,
      );
    } else {
      await vault.unlockFromPath(
        filePath: effectiveFilePath,
        password: passwordController.value,
        keyFilePath: keyFilePath,
        filename: filename,
        yubiKeySlot: yubiKeySlot,
      );
    }
  } on PlatformException catch (e) {
    vault.setErrorWithDetail(
      'FILE_ACCESS_REQUIRED',
      'Select this database again to restore file access.',
      detail: truncateErrorDetail(e.message ?? e.toString()),
    );
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
  } finally {
    if (vault.errorCode == null) {
      final owner = vault is VaultSessionsController
          ? vault.activeSessionId
          : effectiveFilePath;
      securityScopedAccess?.retain(owner: owner);
      retainedAccess = securityScopedAccess != null;
      var bookmark = securityScopedBookmark;
      if ((securityScopedAccess?.stale ?? false) || bookmark == null) {
        bookmark =
            await fileAccess.bookmarkForPath(effectiveFilePath) ?? bookmark;
      }
      if (!kIsWeb) {
        recentDatabases.recordOpened(
          effectiveFilePath,
          filename ?? vault.lastFilename ?? effectiveFilePath,
          securityScopedBookmark: bookmark,
          previousPath: filePath,
        );
      }
    }
    if (!retainedAccess) await securityScopedAccess?.stop();
    if (context.mounted) {
      unlocking.value = false;
      if (vault.errorCode == 'WRONG_PASSWORD') {
        passwordController.value = '';
      }
    }
  }
}
