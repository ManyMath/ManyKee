import 'package:flutter/material.dart';

import 'src/screens/unlock_screen.dart';
import 'src/state/vault_state.dart';
import 'src/theme/app_theme.dart';

void main() {
  runApp(const ManyKeeApp());
}

/// Root widget for the ManyKee Flutter Web vault browser.
class ManyKeeApp extends StatefulWidget {
  const ManyKeeApp({super.key});

  @override
  State<ManyKeeApp> createState() => _ManyKeeAppState();
}

class _ManyKeeAppState extends State<ManyKeeApp> {
  final VaultState _vaultState = VaultState();

  @override
  void dispose() {
    _vaultState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ManyKee',
      theme: appTheme(),
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
          // Placeholder for vault browser (replaced in Plan 03).
          return const Scaffold(
            body: Center(
              child: Text('Vault Browser'),
            ),
          );
        },
      ),
    );
  }
}
