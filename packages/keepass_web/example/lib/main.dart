import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:web/web.dart' as web;

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
  SemanticsHandle? _semanticsHandle;

  bool get _shouldEnableSemantics {
    final params = Uri.parse(web.window.location.href).queryParameters;
    return params['e2e_semantics'] == '1';
  }

  @override
  void initState() {
    super.initState();
    if (_shouldEnableSemantics) {
      _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
    }
  }

  @override
  void dispose() {
    _semanticsHandle?.dispose();
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
