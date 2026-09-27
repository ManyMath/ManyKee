import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': ''};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('a failing fetch shows an error and resets the spinner',
      (tester) async {
    await tester.pumpWidget(wrap(CopyButton(
      fetchValue: () async => throw StateError('boom'),
      clipboardManager: ClipboardManager(),
    )));

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Could not copy'), findsOneWidget);
  });

  testWidgets('a fetch that fails after the button is gone does not throw',
      (tester) async {
    final completer = Completer<String>();
    await tester.pumpWidget(wrap(CopyButton(
      fetchValue: () => completer.future,
      clipboardManager: ClipboardManager(),
    )));

    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Unmount the button while the fetch is still in flight.
    await tester.pumpWidget(wrap(const SizedBox.shrink()));

    completer.completeError(StateError('boom'));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
