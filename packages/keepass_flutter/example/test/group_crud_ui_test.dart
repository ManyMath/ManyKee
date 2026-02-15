import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';
import 'package:keepass_flutter_example/src/screens/vault_screen.dart';

import 'helpers/fake_vault_state.dart';

void main() {
  group('Group CRUD UI', () {
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

    Finder groupLabel(String name) => find.descendant(
          of: find.byType(GroupTree),
          matching: find.text(name),
        );

    Future<void> openGroupMenu(WidgetTester tester, String name) async {
      final tile = find
          .ancestor(
            of: groupLabel(name).first,
            matching: find.byType(Material),
          )
          .first;
      await tester.tap(
        find.descendant(
          of: tile,
          matching: find.byTooltip('Group actions'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('creates a subgroup from the tree', (tester) async {
      await pumpApp(tester);

      await openGroupMenu(tester, 'General');
      await tester.tap(find.text('New Subgroup'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Projects');
      await tester.tap(find.text('Create Group').last);
      await tester.pumpAndSettle();

      expect(groupLabel('Projects'), findsOneWidget);
      expect(vaultState.selectedGroup?.name, 'Projects');
      expect(vaultState.parentOfGroup(vaultState.selectedGroup!.uuid), 'g1');
    });

    testWidgets('renames a nested group from the tree', (tester) async {
      await pumpApp(tester);

      await openGroupMenu(tester, 'Subgroup');
      await tester.tap(find.text('Rename Group'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Renamed Subgroup');
      await tester.tap(find.text('Save Group').last);
      await tester.pumpAndSettle();

      expect(groupLabel('Renamed Subgroup'), findsOneWidget);
      expect(groupLabel('Subgroup'), findsNothing);
      expect(vaultState.parentOfGroup('g1a'), 'g1');
    });
  });
}
