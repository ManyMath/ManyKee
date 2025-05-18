import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'src/screens/unlock_screen.dart';
import 'src/screens/vault_screen.dart';
import 'src/state/web_vault_state.dart';

void main() {
  runApp(const ManyKeeApp());
}

class ManyKeeApp extends StatefulWidget {
  const ManyKeeApp({super.key});

  @override
  State<ManyKeeApp> createState() => _ManyKeeAppState();
}

class _ManyKeeAppState extends State<ManyKeeApp> {
  final WebVaultState _vaultState = WebVaultState();

  @override
  void dispose() {
    _vaultState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          return VaultScreen(vaultState: _vaultState);
        },
      ),
    );
  }
}
