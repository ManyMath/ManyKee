import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'src/screens/lock_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/screens/unlock_screen.dart';
import 'src/screens/vault_screen.dart';
import 'src/services/screen_protection.dart';
import 'src/state/native_auto_lock.dart';
import 'src/state/native_vault_state.dart';
import 'src/state/settings_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsState();
  await settings.init();
  runApp(ManyKeeNativeApp(settings: settings));
}

/// Root widget for the ManyKee native vault browser example.
class ManyKeeNativeApp extends StatefulWidget {
  final SettingsState settings;

  const ManyKeeNativeApp({super.key, required this.settings});

  @override
  State<ManyKeeNativeApp> createState() => _ManyKeeNativeAppState();
}

class _ManyKeeNativeAppState extends State<ManyKeeNativeApp>
    with WidgetsBindingObserver {
  final NativeVaultState _vaultState = NativeVaultState();
  late final NativeAutoLock _autoLock;

  bool _lastIsLocked = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _autoLock = NativeAutoLock(
      vault: _vaultState,
      timeout: widget.settings.autoLockTimeout,
    );
    widget.settings.addListener(_onSettingsChanged);
    _lastIsLocked = _vaultState.isLocked;
    _vaultState.addListener(_onVaultStateChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_onSettingsChanged);
    _vaultState.removeListener(_onVaultStateChanged);
    _autoLock.dispose();
    _vaultState.dispose();
    super.dispose();
  }

  void _onVaultStateChanged() {
    if (_vaultState.isLocked == _lastIsLocked) return;
    _lastIsLocked = _vaultState.isLocked;
    ScreenProtection.setSecure(!_vaultState.isLocked);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ClipboardManager.handleAppLifecycleState(state);
    if (!widget.settings.lockOnBackground) return;
    if (_vaultState.isLocked) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lockVault();
    }
  }

  void _onSettingsChanged() {
    _autoLock.updateTimeout(widget.settings.autoLockTimeout);
  }

  void _lockVault() => _autoLock.lockNow();

  void _onUserActivity() => _autoLock.registerActivity();

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settingsState: widget.settings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        ClipboardManager.configure(
          clearDelay: widget.settings.clipboardAutoClearDelay,
          pasteOnceEnabled: widget.settings.clipboardPasteOnce,
        );

        final ThemeMode themeMode;
        switch (widget.settings.themeMode) {
          case 'light':
            themeMode = ThemeMode.light;
          case 'dark':
            themeMode = ThemeMode.dark;
          default:
            themeMode = ThemeMode.system;
        }

        return MaterialApp(
          title: 'ManyKee',
          theme: ManyKeeTheme.light(),
          darkTheme: ManyKeeTheme.dark(),
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
          home: Listener(
            onPointerDown: (_) => _onUserActivity(),
            onPointerMove: (_) => _onUserActivity(),
            child: ListenableBuilder(
              listenable: _vaultState,
              builder: (context, _) {
                if (_vaultState.isLocked && _vaultState.lastFilePath != null) {
                  return NativeLockScreen(vaultState: _vaultState);
                }

                if (_vaultState.isLocked) {
                  return NativeUnlockScreen(vaultState: _vaultState);
                }

                return NativeVaultScreen(
                  vaultState: _vaultState,
                  onLockPressed: _lockVault,
                  onSettingsPressed: () => _openSettings(context),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
