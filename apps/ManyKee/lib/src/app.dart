import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:keepass_ui/keepass_ui.dart' show ClipboardManager;
import 'package:manyui/manyui.dart';

import 'state/recent_database.dart';
import 'state/manykee_vault_state.dart';
import 'state/settings_state.dart';
import 'state/vault_state_provider.dart';
import 'theme.dart';
import 'unlock/unlock_page.dart';
import 'vault/vault_page.dart';

class ManyKeeApp extends ConsumerStatefulWidget {
  const ManyKeeApp({super.key});

  @override
  ConsumerState<ManyKeeApp> createState() => _ManyKeeAppState();
}

class _ManyKeeAppState extends ConsumerState<ManyKeeApp>
    with WidgetsBindingObserver {
  Timer? _idleTimer;
  ManyKeeSettings? _appliedSettings;
  bool? _appliedLockedState;
  bool? _appliedDirtyState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(ClipboardManager.handleAppLifecycleState(state));
    if (state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused) {
      return;
    }

    final settings = ref.read(manyKeeSettingsProvider);
    final vault = ref.read(vaultStateProvider);
    if (settings.lockOnBackground && _canAutoLock(vault)) {
      unawaited(vault.lock());
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(manyKeeSettingsProvider);
    final mode = ref.watch(themeModeProvider);
    final vault = ref.watch(vaultStateProvider);
    ref.watch(manyKeeSettingsLoaderProvider);
    ref.watch(manyKeeSettingsPersistenceProvider);
    ref.watch(recentDatabasesLoaderProvider);
    ref.watch(recentDatabasesPersistenceProvider);
    _syncRuntimeEffects(settings, vault);

    return MWidgetsApp(
      title: 'ManyKee',
      theme: MThemeData.light(),
      darkTheme: MThemeData.dark(),
      themeMode: mode,
      debugShowCheckedModeBanner: false,
      home: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _handleActivity(),
        onPointerMove: (_) => _handleActivity(),
        onPointerSignal: (_) => _handleActivity(),
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            _handleActivity();
            return KeyEventResult.ignored;
          },
          child: vault.isLocked ? const UnlockPage() : const VaultPage(),
        ),
      ),
    );
  }

  void _syncRuntimeEffects(ManyKeeSettings settings, ManyKeeVaultState vault) {
    ClipboardManager.configure(
      clearDelay: settings.clipboardAutoClearDelay,
      pasteOnceEnabled: settings.clipboardPasteOnce,
    );

    if (_appliedSettings == settings &&
        _appliedLockedState == vault.isLocked &&
        _appliedDirtyState == vault.isDirty) {
      return;
    }
    _appliedSettings = settings;
    _appliedLockedState = vault.isLocked;
    _appliedDirtyState = vault.isDirty;
    _restartIdleTimer(settings, vault);
  }

  void _handleActivity() {
    final settings = ref.read(manyKeeSettingsProvider);
    final vault = ref.read(vaultStateProvider);
    _restartIdleTimer(settings, vault);
  }

  void _restartIdleTimer(ManyKeeSettings settings, ManyKeeVaultState vault) {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_canAutoLock(vault) || settings.autoLockTimeout == Duration.zero) {
      return;
    }

    _idleTimer = Timer(settings.autoLockTimeout, () {
      if (!mounted) return;
      final vault = ref.read(vaultStateProvider);
      if (_canAutoLock(vault)) unawaited(vault.lock());
    });
  }

  bool _canAutoLock(ManyKeeVaultState vault) {
    return !vault.isLocked && !vault.isDirty;
  }
}
