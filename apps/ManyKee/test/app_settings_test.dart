import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manykee/src/services/screen_protection.dart';
import 'package:manyui/manyui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unlock_page_test.dart' show FakeVaultState, appWith;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenProtection.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('auto-lock locks the open vault after inactivity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.settings.autoLockMinutes': 1,
    });
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);

    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(state.isLocked, isTrue);
    expect(find.text('Vault locked'), findsOneWidget);
  });

  testWidgets('auto-lock does not discard unsaved vault changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.settings.autoLockMinutes': 1,
    });
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);
    state.makeDirty();
    await tester.pump();

    await tester.pump(const Duration(minutes: 1));
    await tester.pump();

    expect(state.isLocked, isFalse);
    expect(state.isDirty, isTrue);
    expect(find.text('Unsaved changes'), findsOneWidget);
  });

  testWidgets('backgrounding locks the open vault when enabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.settings.lockOnBackground': true,
      'manykee.settings.autoLockMinutes': 0,
    });
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    expect(state.isLocked, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Vault locked'), findsOneWidget);
  });

  testWidgets('screen protection follows unlocked vault when enabled', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.settings.screenProtection': true,
      'manykee.settings.autoLockMinutes': 0,
    });
    final secureStates = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenProtection.channel, (call) async {
          if (call.method == 'setSecure') {
            final args = call.arguments as Map<Object?, Object?>;
            secureStates.add(args['enabled'] as bool);
          }
          return null;
        });
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');

    try {
      await _unlockVault(tester, state);

      expect(state.isLocked, isFalse);
      expect(secureStates, containsAllInOrder(<bool>[false, true]));

      await state.lock();
      await tester.pump();

      expect(secureStates.last, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('screen protection stays off when disabled', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'manykee.settings.screenProtection': false,
      'manykee.settings.autoLockMinutes': 0,
    });
    final secureStates = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenProtection.channel, (call) async {
          if (call.method == 'setSecure') {
            final args = call.arguments as Map<Object?, Object?>;
            secureStates.add(args['enabled'] as bool);
          }
          return null;
        });
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');

    try {
      await _unlockVault(tester, state);

      expect(state.isLocked, isFalse);
      expect(secureStates, isNot(contains(true)));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Future<void> _unlockVault(WidgetTester tester, FakeVaultState state) async {
  await tester.pumpWidget(appWith(state));
  await tester.pump();

  await tester.tap(find.byType(MTextField));
  await tester.pump();
  await tester.enterText(find.byType(EditableText), 'correct');
  await tester.pump();
  await tester.tap(find.text('Unlock'));
  await tester.pump();
  await tester.pump();

  expect(state.isLocked, isFalse);
}
