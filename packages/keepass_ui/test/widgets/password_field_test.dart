import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';

void main() {
  String clipboardText = '';

  setUp(() {
    clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText =
              (call.arguments as Map<dynamic, dynamic>)['text'] as String? ??
                  '';
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('reveal retries the fetch after a failure', (tester) async {
    var calls = 0;
    await tester.pumpWidget(wrap(PasswordField(
      value: '',
      clipboardManager: ClipboardManager(),
      onFetchValue: () async {
        calls++;
        if (calls == 1) throw StateError('transient');
        return 'hunter2';
      },
    )));

    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(calls, 1);
    expect(find.text('hunter2'), findsNothing);
    // Still hidden; the toggle did not flip on failure.
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('hunter2'), findsOneWidget);
  });

  testWidgets('copy retries the fetch after a failure', (tester) async {
    var calls = 0;
    final clipboardManager = ClipboardManager();
    await tester.pumpWidget(wrap(PasswordField(
      value: '',
      clipboardManager: clipboardManager,
      onFetchValue: () async {
        calls++;
        if (calls == 1) throw StateError('transient');
        return 'hunter2';
      },
    )));

    await tester.tap(find.byTooltip('Copy password'));
    await tester.pump();
    await tester.pump();

    expect(calls, 1);
    expect(find.textContaining('Could not copy'), findsOneWidget);
    expect(clipboardText, '');

    await tester.tap(find.byTooltip('Copy password'));
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(clipboardText, 'hunter2');

    // Flush the check-mark and auto-clear timers so none are left pending.
    clipboardManager.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
}
