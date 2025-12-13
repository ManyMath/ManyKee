import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:web/web.dart' as web;

import 'src/screens/unlock_screen.dart';
import 'src/screens/vault_screen.dart';
import 'src/state/settings_state.dart';
import 'src/state/web_vault_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsState();
  await settings.init();
  runApp(ManyKeeApp(settings: settings));
}

class ManyKeeApp extends StatefulWidget {
  final SettingsState settings;

  const ManyKeeApp({super.key, required this.settings});

  @override
  State<ManyKeeApp> createState() => _ManyKeeAppState();
}

class _ManyKeeAppState extends State<ManyKeeApp> with WidgetsBindingObserver {
  final WebVaultState _vaultState = WebVaultState();
  SemanticsHandle? _semanticsHandle;

  bool get _shouldEnableSemantics {
    final params = Uri.parse(web.window.location.href).queryParameters;
    return params['e2e_semantics'] == '1';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_shouldEnableSemantics) {
      _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _semanticsHandle?.dispose();
    _vaultState.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ClipboardManager.handleAppLifecycleState(state);
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

        return MaterialApp(
          title: 'ManyKee',
          theme: ManyKeeTheme.light(),
          debugShowCheckedModeBanner: false,
          home: ListenableBuilder(
            listenable: _vaultState,
            builder: (context, _) {
              if (_vaultState.isLocked) {
                return UnlockScreen(
                  vaultState: _vaultState,
                  isLockScreen: _vaultState.lastFilename != null,
                );
              }
              return VaultScreen(
                vaultState: _vaultState,
                settingsState: widget.settings,
              );
            },
          ),
        );
      },
    );
  }
}
