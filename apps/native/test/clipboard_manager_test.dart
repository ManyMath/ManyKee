import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_ui/keepass_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardManager', () {
    late ClipboardManager manager;
    String clipboardText = '';

    setUp(() {
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

    testWidgets('uses configured success messaging for subsequent copies',
        (tester) async {
      final firstCopy = await manager.copyWithAutoClear('secret-a');
      expect(firstCopy, isTrue);
      expect(manager.lastSuccessMessage, 'Copied to clipboard (clears in 30s)');

      ClipboardManager.configure(
        clearDelay: const Duration(seconds: 10),
        pasteOnceEnabled: true,
      );
      final secondCopy = await manager.copyWithAutoClear('secret-b');

      expect(secondCopy, isTrue);
      expect(
        manager.lastSuccessMessage,
        'Copied to clipboard (10s clear or next resume)',
      );
      final data = await Clipboard.getData('text/plain');
      expect(data?.text, 'secret-b');
      manager.dispose();
    });

    testWidgets('paste-once mode clears clipboard on resume', (tester) async {
      ClipboardManager.configure(
        clearDelay: Duration.zero,
        pasteOnceEnabled: true,
      );

      final copied = await manager.copyWithAutoClear('secret-c');
      expect(copied, isTrue);

      var data = await Clipboard.getData('text/plain');
      expect(data?.text, 'secret-c');

      await ClipboardManager.handleAppLifecycleState(AppLifecycleState.resumed);

      data = await Clipboard.getData('text/plain');
      expect(data?.text, '');
      expect(
        manager.lastSuccessMessage,
        'Copied to clipboard (clears on next resume)',
      );
      manager.dispose();
    });

    testWidgets('dispose clears clipboard when a clear was pending',
        (tester) async {
      final copied = await manager.copyWithAutoClear('secret-d');
      expect(copied, isTrue);

      var data = await Clipboard.getData('text/plain');
      expect(data?.text, 'secret-d');

      manager.dispose();
      await tester.pump();

      data = await Clipboard.getData('text/plain');
      expect(data?.text, '');
    });

    testWidgets('dispose does not touch clipboard when no clear was pending',
        (tester) async {
      ClipboardManager.configure(
        clearDelay: Duration.zero,
        pasteOnceEnabled: false,
      );

      final copied = await manager.copyWithAutoClear('secret-e');
      expect(copied, isTrue);

      var data = await Clipboard.getData('text/plain');
      expect(data?.text, 'secret-e');

      manager.dispose();
      await tester.pump();

      data = await Clipboard.getData('text/plain');
      expect(data?.text, 'secret-e');
    });
  });
}
