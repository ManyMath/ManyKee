import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manykee/src/state/security_scoped_file_access.dart';

const _channel = MethodChannel('com.manykee.native/security_scoped_files');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('a retained lease can be stopped explicitly', () async {
    final stopped = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'startAccessingBookmark') {
            return <String, Object?>{
              'token': 'token-1',
              'path': '/tmp/one.kdbx',
              'stale': false,
            };
          }
          if (call.method == 'stopAccessing') {
            stopped.add(
              (call.arguments as Map<Object?, Object?>)['token']! as String,
            );
            return null;
          }
          fail('Unexpected method ${call.method}');
        });
    final access = SecurityScopedFileAccess(channel: _channel);
    final lease = await access.startFromBookmark('bookmark');
    lease!.retain(owner: 'vault-1');

    await lease.stop();
    await access.releaseAll();

    expect(stopped, <String>['token-1']);
  });

  test('releaseOwner stops only leases owned by that vault session', () async {
    var nextToken = 0;
    final stopped = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'startAccessingBookmark') {
            nextToken++;
            return <String, Object?>{
              'token': 'token-$nextToken',
              'path': '/tmp/$nextToken.kdbx',
              'stale': false,
            };
          }
          if (call.method == 'stopAccessing') {
            stopped.add(
              (call.arguments as Map<Object?, Object?>)['token']! as String,
            );
            return null;
          }
          fail('Unexpected method ${call.method}');
        });
    final access = SecurityScopedFileAccess(channel: _channel);
    final first = await access.startFromBookmark('first');
    final second = await access.startFromBookmark('second');
    first!.retain(owner: 'vault-1');
    second!.retain(owner: 'vault-2');

    await access.releaseOwner('vault-1');
    expect(stopped, <String>['token-1']);

    await access.releaseAll();
    expect(stopped, <String>['token-1', 'token-2']);
  });
}
