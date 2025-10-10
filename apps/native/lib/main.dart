import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'src/screens/lock_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/screens/unlock_screen.dart';
import 'src/screens/vault_screen.dart';
import 'src/state/native_idle_timer.dart';
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
  late final NativeIdleTimer _idleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _idleTimer = NativeIdleTimer(timeout: widget.settings.autoLockTimeout);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer.dispose();
    _vaultState.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.settings.lockOnBackground) return;
    if (_vaultState.isLocked) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _lockVault();
    }
  }

  void _lockVault() {
    if (!_vaultState.isLocked) {
      _idleTimer.stop();
      _vaultState.lock();
    }
  }

  void _onVaultUnlocked() {
    _idleTimer.updateTimeout(widget.settings.autoLockTimeout);
    _idleTimer.start(_lockVault);
  }

  void _onUserActivity() {
    if (!_vaultState.isLocked) {
      _idleTimer.resetTimer();
    }
  }

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
        _idleTimer.updateTimeout(widget.settings.autoLockTimeout);

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

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_vaultState.isLocked) {
                    _onVaultUnlocked();
                  }
                });

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
