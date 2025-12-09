import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:manykee_native/src/screens/settings_screen.dart';
import 'package:manykee_native/src/state/settings_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsScreen', () {
    late SettingsState settingsState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settingsState = SettingsState();
      await settingsState.init();
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(settingsState: settingsState),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows clipboard controls and disabled provider toggles',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('Clipboard auto-clear'), findsOneWidget);
      expect(find.text('Paste-once clipboard'), findsOneWidget);
      expect(find.text('Biometric unlock'), findsOneWidget);
      expect(find.text('Autofill'), findsOneWidget);
      expect(find.text('not supported on this platform'), findsOneWidget);
      expect(find.text('coming soon'), findsOneWidget);

      await tester.tap(find.text('30 seconds').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('10 seconds').last);
      await tester.pumpAndSettle();

      await tester
          .tap(find.widgetWithText(SwitchListTile, 'Paste-once clipboard'));
      await tester.pumpAndSettle();

      expect(settingsState.clipboardAutoClearSeconds, 10);
      expect(settingsState.clipboardPasteOnce, isTrue);

      final biometricTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Biometric unlock'),
      );
      final autofillTile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Autofill'),
      );
      expect(biometricTile.onChanged, isNull);
      expect(autofillTile.onChanged, isNull);
    });
  });
}
