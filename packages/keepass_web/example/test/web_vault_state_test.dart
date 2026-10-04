@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_web/keepass_web.dart';
import 'package:keepass_web_example/src/state/web_file_storage_provider.dart';
import 'package:keepass_web_example/src/state/web_vault_state.dart';

class _FakeKeePassWebApi extends KeePassWebApi {
  final savedPasswords = <String>[];
  String? openedWith;

  @override
  Future<void> init() async {}

  @override
  Future<int> openDatabase(List<int> dbBytes,
      {required String password}) async {
    openedWith = 'password';
    return 1;
  }

  @override
  Future<int> openDatabaseWithChallengeResponse(
    List<int> dbBytes, {
    required String password,
    required String challengeResponseHex,
  }) async {
    openedWith = 'challenge-response';
    return 1;
  }

  @override
  Future<void> closeDatabase(int handle) async {}

  @override
  Future<List<Map<String, dynamic>>> listGroups(
    int handle,
    String groupUuid,
  ) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> listEntries(
    int handle,
    String groupUuid,
  ) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<String> createEntry(int handle, String groupUuid) async => 'entry-1';

  @override
  Future<List<int>> saveDatabase(
    int handle, {
    required String password,
    List<int>? keyFileBytes,
  }) async {
    savedPasswords.add(password);
    return const <int>[1, 2, 3];
  }
}

class _RecordingStorage extends WebFileStorageProvider {
  final savedNames = <String>[];

  @override
  Future<void> save(Uint8List bytes, {required String name}) async {
    savedNames.add(name);
  }
}

void main() {
  late _FakeKeePassWebApi api;
  late _RecordingStorage storage;
  late WebVaultState state;

  setUp(() {
    api = _FakeKeePassWebApi();
    storage = _RecordingStorage();
    state = WebVaultState(api: api, storageProvider: storage);
  });

  tearDown(() => state.dispose());

  test('refuses to save a vault unlocked with a challenge-response', () async {
    await state.unlock(
      dbBytes: Uint8List(4),
      password: 'demopass',
      challengeResponseHex: 'ab' * 20,
      filename: 'yubikey.kdbx',
    );
    expect(api.openedWith, 'challenge-response');
    await state.createEntry('');
    expect(state.isDirty, isTrue);

    await expectLater(
      state.saveDatabase(password: 'demopass'),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('YubiKey-protected databases is not supported on web'),
        ),
      ),
    );
    expect(api.savedPasswords, isEmpty);
    expect(storage.savedNames, isEmpty);
    expect(state.isDirty, isTrue);
  });

  test('saves a password-only vault', () async {
    await state.unlock(
      dbBytes: Uint8List(4),
      password: 'demopass',
      filename: 'plain.kdbx',
    );
    await state.createEntry('');

    await state.saveDatabase(password: 'demopass');
    expect(api.savedPasswords, <String>['demopass']);
    expect(storage.savedNames, <String>['plain.kdbx']);
    expect(state.isDirty, isFalse);
  });

  test('a later password-only unlock re-enables saving', () async {
    await state.unlock(
      dbBytes: Uint8List(4),
      password: 'demopass',
      challengeResponseHex: 'ab' * 20,
      filename: 'vault.kdbx',
    );
    await state.lock();
    await state.unlock(
      dbBytes: Uint8List(4),
      password: 'demopass',
      filename: 'vault.kdbx',
    );

    await state.saveDatabase(password: 'demopass');
    expect(api.savedPasswords, <String>['demopass']);
  });
}
