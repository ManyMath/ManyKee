import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:manykee_native/src/screens/vault_screen.dart';

import 'helpers/fake_vault_state.dart';

class _DirtyVault extends FakeVaultState {
  _DirtyVault() {
    markDirty();
  }

  int lockCalls = 0;

  @override
  Future<void> lock() {
    lockCalls++;
    return super.lock();
  }
}

void main() {
  late _DirtyVault vault;

  setUp(() {
    vault = _DirtyVault();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ManyKeeTheme.light(),
        home: NativeVaultScreen(vaultState: vault),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('locking a dirty vault asks first and Cancel keeps it open', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Lock Vault'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(vault.lockCalls, 0);
    expect(vault.isLocked, isFalse);
    expect(vault.isDirty, isTrue);
  });

  testWidgets('Discard locks the dirty vault', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Lock Vault'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(vault.lockCalls, 1);
    expect(vault.isLocked, isTrue);
  });
}
