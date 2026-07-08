import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manykee/src/services/screen_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenProtection.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('setSecure sends enabled flag on supported platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenProtection.channel, (call) async {
          calls.add(call);
          return null;
        });

    await ScreenProtection.setSecure(true);
    await ScreenProtection.setSecure(false);

    expect(calls, hasLength(2));
    expect(calls[0].method, 'setSecure');
    expect(calls[0].arguments, <String, Object>{'enabled': true});
    expect(calls[1].method, 'setSecure');
    expect(calls[1].arguments, <String, Object>{'enabled': false});
  });

  test('setSecure is a no-op on unsupported platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var callCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScreenProtection.channel, (call) async {
          callCount += 1;
          return null;
        });

    await ScreenProtection.setSecure(true);

    expect(callCount, 0);
  });

  test('setSecure ignores a missing native handler', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await expectLater(ScreenProtection.setSecure(true), completes);
    await expectLater(ScreenProtection.setSecure(false), completes);
  });
}
