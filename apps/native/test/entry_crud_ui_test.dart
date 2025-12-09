import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:manykee_native/src/screens/vault_screen.dart';

import 'helpers/fake_vault_state.dart';

void main() {
  group('Entry CRUD UI', () {
    late FakeVaultState vaultState;

    setUp(() {
      vaultState = FakeVaultState();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: ManyKeeTheme.light(),
          home: NativeVaultScreen(vaultState: vaultState),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('creates an entry with generated password', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('New Entry'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Created Entry');
      await tester.enterText(fields.at(1), 'created-user');
      await tester.tap(find.byTooltip('Generate password'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Entry').last);
      await tester.pumpAndSettle();

      expect(find.text('Created Entry'), findsWidgets);
      expect(vaultState.entries.any((entry) => entry.title == 'Created Entry'),
          isTrue);

      final createdEntry = vaultState.entries.firstWhere(
        (entry) => entry.title == 'Created Entry',
      );
      final createdFields = await vaultState.readEntryFields(createdEntry.uuid);
      expect((createdFields['Password'] as String?)?.isNotEmpty, isTrue);
    });

    testWidgets('edits and deletes an entry from the detail panel',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Sample Entry').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit Entry'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'updated-user');
      await tester.tap(find.text('Save Entry').last);
      await tester.pumpAndSettle();

      expect(find.text('updated-user'), findsWidgets);

      await tester.tap(find.byTooltip('Delete Entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Entry'));
      await tester.pumpAndSettle();

      expect(find.text('Sample Entry'), findsNothing);
    });

    testWidgets('moves an entry to another group', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Sample Entry').first);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Move Entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move Entry').last);
      await tester.pumpAndSettle();

      expect(vaultState.entries.any((entry) => entry.title == 'Sample Entry'),
          isFalse);

      await vaultState.selectGroup(vaultState.groups[1]);
      expect(vaultState.entries.any((entry) => entry.title == 'Sample Entry'),
          isTrue);
    });

    testWidgets('shows a live TOTP code with countdown', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Sample Entry').first);
      await tester.pumpAndSettle();

      expect(find.text('One-Time Code'), findsOneWidget);
      expect(find.text('806 863'), findsOneWidget);
      expect(find.text('Refreshes in 26s of 30s'), findsOneWidget);
      expect(find.byTooltip('Copy one-time code'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Refreshes in 25s of 30s'), findsOneWidget);
    });
  });
}
