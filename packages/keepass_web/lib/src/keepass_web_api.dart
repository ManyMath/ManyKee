import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'entry_payload.dart';
import 'worker_bridge.dart';
import 'worker_error.dart';

class KeePassWebApi {
  final WorkerBridge _bridge = WorkerBridge();

  Stream<int> get progress => _bridge.progress;

  Future<void> init() => _bridge.init();

  Future<int> createDatabase() async {
    final result = await _bridge.call('create_db', const []);
    final json = jsonDecode(result) as Map<String, dynamic>;
    return json['handle'] as int;
  }

  Future<int> openDatabase(List<int> dbBytes,
      {required String password}) async {
    final result = await _bridge.call('open_db', [
      Uint8List.fromList(dbBytes),
      password,
      null, // no key file
    ]);
    final json = jsonDecode(result) as Map<String, dynamic>;
    return json['handle'] as int;
  }

  Future<int> openDatabaseWithKeyFile(
    List<int> dbBytes, {
    required String password,
    required List<int> keyFileBytes,
  }) async {
    final result = await _bridge.call('open_db', [
      Uint8List.fromList(dbBytes),
      password,
      Uint8List.fromList(keyFileBytes),
    ]);
    final json = jsonDecode(result) as Map<String, dynamic>;
    return json['handle'] as int;
  }

  Future<int> openDatabaseWithChallengeResponse(
    List<int> dbBytes, {
    required String password,
    required String challengeResponseHex,
  }) async {
    final result = await _bridge.call('open_db_with_challenge_response', [
      Uint8List.fromList(dbBytes),
      password,
      challengeResponseHex,
    ]);
    final json = jsonDecode(result) as Map<String, dynamic>;
    return json['handle'] as int;
  }

  Future<void> closeDatabase(int handle) async {
    await _bridge.call('close_db', [handle]);
  }

  Future<List<Map<String, dynamic>>> listGroups(
      int handle, String groupUuid) async {
    final result = await _bridge.call('list_groups', [handle, groupUuid]);
    final list = jsonDecode(result) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listEntries(
      int handle, String groupUuid) async {
    final result = await _bridge.call('list_entries', [handle, groupUuid]);
    final list = jsonDecode(result) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> readEntryFields(
      int handle, String entryUuid) async {
    final result = await _bridge.call('read_entry_fields', [handle, entryUuid]);
    final payload = jsonDecode(result) as Map<String, dynamic>;
    return normalizeEntryFieldsPayload(payload);
  }

  Future<String?> readEntryField(
    int handle,
    String entryUuid,
    String fieldName,
  ) async {
    try {
      return await _bridge.call(
        'read_entry_field',
        [handle, entryUuid, fieldName],
      );
    } on KeePassWebError {
      return null;
    }
  }

  Future<String> createEntry(int handle, String groupUuid) async {
    final result = await _bridge.call('create_entry', [handle, groupUuid, '']);
    final json = jsonDecode(result) as Map<String, dynamic>;
    return json['uuid'] as String;
  }

  Future<void> setEntryField(
    int handle,
    String entryUuid,
    String field,
    String value, {
    bool isProtected = false,
  }) async {
    await _bridge.call('set_entry_field', [
      handle,
      entryUuid,
      field,
      value,
      isProtected,
    ]);
  }

  Future<void> deleteEntry(int handle, String entryUuid) async {
    await _bridge.call('delete_entry', [handle, entryUuid]);
  }

  Future<void> moveEntry(
    int handle,
    String entryUuid,
    String targetGroupUuid,
  ) async {
    await _bridge.call('move_entry', [handle, entryUuid, targetGroupUuid]);
  }

  Future<String> createGroup(int handle, String parentUuid, String name) async {
    final result =
        await _bridge.call('create_group', [handle, parentUuid, name]);
    final json = jsonDecode(result) as Map<String, dynamic>;
    return json['uuid'] as String;
  }

  Future<void> renameGroup(int handle, String groupUuid, String name) async {
    await _bridge.call('rename_group', [handle, groupUuid, name]);
  }

  Future<void> deleteGroup(int handle, String groupUuid) async {
    await _bridge.call('delete_group', [handle, groupUuid]);
  }

  Future<void> moveGroup(
    int handle,
    String groupUuid,
    String targetParentUuid,
  ) async {
    await _bridge.call('move_group', [handle, groupUuid, targetParentUuid]);
  }

  /// Re-encrypts the database with [password] and optional [keyFileBytes].
  ///
  /// The wasm core cannot write a challenge-response (YubiKey) factor, so a
  /// database opened with [openDatabaseWithChallengeResponse] must not be
  /// saved through this method: the result would silently drop that factor.
  Future<List<int>> saveDatabase(
    int handle, {
    required String password,
    List<int>? keyFileBytes,
  }) async {
    final result = await _bridge.call('save_db', [
      handle,
      password,
      keyFileBytes == null ? null : Uint8List.fromList(keyFileBytes),
    ]);
    return _decodeHex(result);
  }

  Future<Map<String, dynamic>?> getTotpCode(int handle, String entryUuid) {
    return _bridge.call('get_totp', [handle, entryUuid]).then((result) {
      final decoded = jsonDecode(result);
      if (decoded == null) {
        return null;
      }
      return Map<String, dynamic>.from(decoded as Map<String, dynamic>);
    });
  }

  Future<Map<String, dynamic>> mergeDatabases(int handleA, int handleB) async {
    final result = await _bridge.call('merge_databases', [handleA, handleB]);
    return jsonDecode(result) as Map<String, dynamic>;
  }

  Future<String> extractChallenge(List<int> dbBytes) async {
    return await _bridge.call('extract_challenge', [
      Uint8List.fromList(dbBytes),
    ]);
  }

  Future<void> dispose() async {
    _bridge.dispose();
  }

  List<int> _decodeHex(String value) {
    if (value.length.isOdd) {
      throw const FormatException('Invalid hex string length');
    }

    final bytes = Uint8List(value.length ~/ 2);
    for (var i = 0; i < value.length; i += 2) {
      bytes[i ~/ 2] = int.parse(value.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }
}
