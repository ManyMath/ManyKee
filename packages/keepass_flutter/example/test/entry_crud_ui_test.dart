import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:keepass_flutter_example/src/screens/vault_screen.dart';

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
      expect(
        vaultState.entries.any((entry) => entry.title == 'Created Entry'),
        isTrue,
      );

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
  });
}
