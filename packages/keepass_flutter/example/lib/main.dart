import 'package:flutter/material.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'src/screens/unlock_screen.dart';
import 'src/screens/vault_screen.dart';
import 'src/state/native_vault_state.dart';

void main() {
  runApp(const ManyKeeNativeApp());
}

/// Root widget for the ManyKee native vault browser example.
class ManyKeeNativeApp extends StatefulWidget {
  const ManyKeeNativeApp({super.key});

  @override
  State<ManyKeeNativeApp> createState() => _ManyKeeNativeAppState();
}

class _ManyKeeNativeAppState extends State<ManyKeeNativeApp> {
  final NativeVaultState _vaultState = NativeVaultState();

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
            return NativeUnlockScreen(vaultState: _vaultState);
          }
          return NativeVaultScreen(vaultState: _vaultState);
        },
      ),
    );
  }
}
