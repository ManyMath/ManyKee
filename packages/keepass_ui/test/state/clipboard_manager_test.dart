import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardManager auto-clear', () {
    late ClipboardManager manager;
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
      ClipboardManager.configure(
        clearDelay: const Duration(seconds: 30),
        pasteOnceEnabled: false,
      );
      manager = ClipboardManager();
    });

    tearDown(() {
      manager.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('timer clears the clipboard when it still holds our value',
        (tester) async {
      expect(await manager.copyWithAutoClear('secret'), isTrue);
      expect(clipboardText, 'secret');

      await tester.pump(const Duration(seconds: 31));

      expect(clipboardText, '');
    });

    testWidgets('timer preserves content copied elsewhere in the meantime',
        (tester) async {
      expect(await manager.copyWithAutoClear('secret'), isTrue);

      // The user copies something else (e.g. a URL) before the timer fires.
      clipboardText = 'https://example.com';

      await tester.pump(const Duration(seconds: 31));

      expect(clipboardText, 'https://example.com');
    });

    testWidgets('paste-once resume preserves foreign clipboard content',
        (tester) async {
      ClipboardManager.configure(
        clearDelay: Duration.zero,
        pasteOnceEnabled: true,
      );
      expect(await manager.copyWithAutoClear('secret'), isTrue);

      clipboardText = 'something else';
      await ClipboardManager.handleAppLifecycleState(AppLifecycleState.resumed);

      expect(clipboardText, 'something else');
    });

    testWidgets('dispose preserves foreign clipboard content', (tester) async {
      expect(await manager.copyWithAutoClear('secret'), isTrue);

      clipboardText = 'something else';
      manager.dispose();
      await tester.pump();

      expect(clipboardText, 'something else');
    });

    testWidgets('dispose still clears our own pending value', (tester) async {
      expect(await manager.copyWithAutoClear('secret'), isTrue);

      manager.dispose();
      await tester.pump();

      expect(clipboardText, '');
    });
  });
}
