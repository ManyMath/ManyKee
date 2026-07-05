import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:manyui/manyui.dart';

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
            onPressed: () {
              final mode = ref.read(themeModeProvider);
              ref.read(themeModeProvider.notifier).state =
                  mode == MThemeMode.dark ? MThemeMode.light : MThemeMode.dark;
            },
            semanticLabel: 'Toggle theme',
            child: MIcon(ref.watch(themeModeProvider) == MThemeMode.dark
                ? MIconData.sun
                : MIconData.moon),
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

    final filePath = useState<String?>(null);
    final filename = useState<String?>(null);
    final keyFilePath = useState<String?>(null);
    final keyFilename = useState<String?>(null);
    final password = useState('');
    final unlocking = useState(false);
    final passwordController = _usePasswordController();
    final yubiKeyAttempt = useState(0);
    final yubiKeys = _useYubiKeys(ref, yubiKeyAttempt.value);
    final useYubiKey = useState(false);

    final canUnlock =
        filePath.value != null && password.value.isNotEmpty && !unlocking.value;

    Future<void> pickDatabase() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['kdbx'],
        dialogTitle: 'Choose KDBX File',
      );
      if (result != null && result.files.isNotEmpty) {
        filePath.value = result.files.single.path;
        filename.value = result.files.single.name;
      }
    }

    Future<void> pickKeyFile() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['key', 'keyx', 'xml'],
        dialogTitle: 'Choose Key File',
      );
      if (result != null && result.files.isNotEmpty) {
        keyFilePath.value = result.files.single.path;
        keyFilename.value = result.files.single.name;
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
        keyFilePath: keyFilePath.value,
        filename: filename.value,
        yubiKeySlot:
            useYubiKey.value && (yubiKeys.value?.isNotEmpty ?? false)
                ? '2'
                : null,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Unlock a database', style: theme.typography.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Open a KeePass (.kdbx) file to get started.',
          style: theme.typography.bodySmall
              .copyWith(color: theme.colors.mutedForeground),
        ),
        const SizedBox(height: 24),
        const MLabel('Database'),
        const SizedBox(height: 8),
        MButton(
          variant: MButtonVariant.outline,
          onPressed: unlocking.value ? null : pickDatabase,
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
          onPressed: unlocking.value ? null : pickKeyFile,
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
          enabled: !unlocking.value,
          onChanged: (value) => password.value = value,
          onSubmitted: (_) => unlock(),
        ),
        _YubiKeyOption(
          yubiKeys: yubiKeys.value,
          useYubiKey: useYubiKey,
          enabled: !unlocking.value,
          onRedetect: () {
            yubiKeys.value = null;
            yubiKeyAttempt.value++;
          },
        ),
        _UnlockStatus(
          unlocking: unlocking.value,
          usingYubiKey: useYubiKey.value && (yubiKeys.value?.isNotEmpty ?? false),
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
          style: theme.typography.bodySmall
              .copyWith(color: theme.colors.mutedForeground),
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
            style: theme.typography.bodySmall
                .copyWith(color: theme.colors.destructive),
          ),
          if (errorDetail != null) ...[
            const SizedBox(height: 4),
            Text(
              errorDetail,
              style: theme.typography.caption
                  .copyWith(color: theme.colors.mutedForeground),
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
                style: theme.typography.caption
                    .copyWith(color: theme.colors.mutedForeground),
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
    WidgetRef ref, int attempt) {
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
    final captionStyle = theme.typography.caption
        .copyWith(color: theme.colors.mutedForeground);
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
            Expanded(
              child: Text('No YubiKey detected.', style: captionStyle),
            ),
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

/// Owns a disposed-with-the-widget [MController] for the password field so
/// the form can clear it after a wrong-password attempt.
MController<String> _usePasswordController() {
  final controller = useMemoized(() => MController<String>(''));
  useEffect(() => controller.dispose, <Object?>[controller]);
  return controller;
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
  String? filename,
  String? yubiKeySlot,
}) async {
  final vault = ref.read(vaultStateProvider);
  unlocking.value = true;
  try {
    await vault.unlockFromPath(
      filePath: filePath,
      password: passwordController.value,
      keyFilePath: keyFilePath,
      filename: filename,
      yubiKeySlot: yubiKeySlot,
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
  }
  if (!context.mounted) return;
  unlocking.value = false;
  if (vault.errorCode == 'WRONG_PASSWORD') {
    passwordController.value = '';
    password.value = '';
  }
}
