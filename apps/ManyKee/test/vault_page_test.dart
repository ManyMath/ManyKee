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
    expect(button.onPressed, isNotNull,
        reason: 'the button must be enabled once a vault with a known '
            'file path is open, not left disabled');
  });
}
