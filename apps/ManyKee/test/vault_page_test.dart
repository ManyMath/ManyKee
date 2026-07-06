import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manyui/manyui.dart';

import 'unlock_page_test.dart' show FakeVaultState, appWith;

void main() {
  testWidgets(
    'vault page exposes a merge-databases entry point once unlocked',
    (tester) async {
      final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
      await tester.pumpWidget(appWith(state));

      await tester.tap(find.byType(MTextField));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'correct');
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump();

      expect(state.isLocked, isFalse);
      expect(find.text('Merge databases…'), findsOneWidget);

      final button = tester.widget<MButton>(
        find.ancestor(
          of: find.text('Merge databases…'),
          matching: find.byType(MButton),
        ),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason:
            'the button must be enabled once a vault with a known '
            'file path is open, not left disabled',
      );
    },
  );

  testWidgets('dirty vault exposes save controls and saves with password', (
    tester,
  ) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);

    state.makeDirty();
    await tester.pump();

    expect(find.text('Unsaved changes'), findsOneWidget);
    expect(find.widgetWithText(MButton, 'Save changes'), findsOneWidget);
    expect(find.widgetWithText(MButton, 'Discard'), findsOneWidget);

    await tester.tap(find.widgetWithText(MButton, 'Save changes'));
    await tester.pump();

    final passwordField = find.descendant(
      of: find.byType(MDialog),
      matching: find.byType(EditableText),
    );
    expect(passwordField, findsOneWidget);

    await tester.enterText(passwordField, 'save-pass');
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Save')),
    );
    await tester.pump();
    await tester.pump();

    expect(state.savedPasswords, <String>['save-pass']);
    expect(state.isDirty, isFalse);
    expect(state.isLocked, isFalse);
    expect(find.text('Unsaved changes'), findsNothing);
  });

  testWidgets('dirty lock can be cancelled without losing changes', (
    tester,
  ) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);
    state.makeDirty();
    await tester.pump();

    await tester.tap(find.widgetWithText(MButton, 'Lock'));
    await tester.pump();

    expect(find.text('Unsaved changes'), findsWidgets);
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Cancel')),
    );
    await tester.pump();

    expect(state.isLocked, isFalse);
    expect(state.isDirty, isTrue);
    expect(find.widgetWithText(MButton, 'Lock'), findsOneWidget);
  });

  testWidgets('dirty lock can save first and then lock', (tester) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);
    state.makeDirty();
    await tester.pump();

    await tester.tap(find.widgetWithText(MButton, 'Lock'));
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Save')),
    );
    await tester.pump();

    final passwordField = find.descendant(
      of: find.byType(MDialog),
      matching: find.byType(EditableText),
    );
    await tester.enterText(passwordField, 'save-before-lock');
    await tester.pump();
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Save')),
    );
    await tester.pump();
    await tester.pump();

    expect(state.savedPasswords, <String>['save-before-lock']);
    expect(state.isLocked, isTrue);
    expect(state.isDirty, isFalse);
    expect(find.text('Vault locked'), findsOneWidget);
  });

  testWidgets('dirty discard confirms and locks without saving', (
    tester,
  ) async {
    final state = FakeVaultState(initialFilePath: '/tmp/vault.kdbx');
    await _unlockVault(tester, state);
    state.makeDirty();
    await tester.pump();

    await tester.tap(find.widgetWithText(MButton, 'Discard'));
    await tester.pump();

    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(MDialog), matching: find.text('Discard')),
    );
    await tester.pump();
    await tester.pump();

    expect(state.savedPasswords, isEmpty);
    expect(state.isLocked, isTrue);
    expect(state.isDirty, isFalse);
    expect(find.text('Vault locked'), findsOneWidget);
  });
}

Future<void> _unlockVault(WidgetTester tester, FakeVaultState state) async {
  await tester.pumpWidget(appWith(state));

  await tester.tap(find.byType(MTextField));
  await tester.pump();
  await tester.enterText(find.byType(EditableText), 'correct');
  await tester.pump();
  await tester.tap(find.text('Unlock'));
  await tester.pump();
  await tester.pump();

  expect(state.isLocked, isFalse);
}
