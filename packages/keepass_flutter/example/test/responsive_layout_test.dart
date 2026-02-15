import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_flutter_example/src/screens/vault_screen.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'helpers/fake_vault_state.dart';

void main() {
  group('Responsive layout breakpoints', () {
    late FakeVaultState vaultState;

    setUp(() {
      vaultState = FakeVaultState();
    });

    Widget buildApp() {
      return MaterialApp(
        theme: ManyKeeTheme.light(),
        home: NativeVaultScreen(vaultState: vaultState),
      );
    }

    testWidgets('desktop (>900px): three panels, no menu button',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.menu), findsNothing);
      expect(find.byType(GroupTree), findsOneWidget);
      expect(find.byType(EntryList), findsOneWidget);
      expect(find.byType(EntryDetailEmpty), findsOneWidget);
    });

    testWidgets('mobile (<600px): navigation stack, ManyKee title',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('ManyKee'), findsOneWidget);
      expect(find.byType(EntryList), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);

      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('ManyKee'), findsNothing);
    });
  });
}
