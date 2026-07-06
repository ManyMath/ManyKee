import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:keepass/keepass.dart';

import 'worker_bridge.dart';
import 'worker_error.dart';

class KeePassWebApi implements KeePassApi {
  final WorkerBridge _bridge = WorkerBridge();

  @override
  Stream<int> get progress => _bridge.progress;

  @override
  Future<void> init() => _bridge.init();

  @override
  Future<int> createDatabase() async {
    final result = await _bridge.call('create_db', const []);
    final json = jsonDecode(result) as Map<String, dynamic>;
    return json['handle'] as int;
  }

  @override
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

  @override
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

  @override
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

  @override
  Future<void> closeDatabase(int handle) async {
    await _bridge.call('close_db', [handle]);
  }

  @override
  Future<List<Map<String, dynamic>>> listGroups(
      int handle, String groupUuid) async {
    final result = await _bridge.call('list_groups', [handle, groupUuid]);
    final list = jsonDecode(result) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> listEntries(
      int handle, String groupUuid) async {
    final result = await _bridge.call('list_entries', [handle, groupUuid]);
    final list = jsonDecode(result) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(
      int handle, String entryUuid) async {
    final result = await _bridge.call('read_entry_fields', [handle, entryUuid]);
    final payload = jsonDecode(result) as Map<String, dynamic>;
    final fields = (payload['fields'] as Map?)?.cast<String, dynamic>();
    if (fields == null) {
      return payload;
    }

    return <String, dynamic>{
      ...fields,
      'custom_data':
          (payload['custom_data'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
      'protected':
          (payload['protected'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{},
    };
  }

  @override
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

  @override
  Future<String> createEntry(int handle, String groupUuid) async {
    final result = await _bridge.call('create_entry', [handle, groupUuid, '']);
    final json = jsonDecode(result) as Map<String, dynamic>;
    return json['uuid'] as String;
  }

  @override
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

  @override
  Future<void> deleteEntry(int handle, String entryUuid) async {
    await _bridge.call('delete_entry', [handle, entryUuid]);
  }

  @override
  Future<void> moveEntry(
    int handle,
    String entryUuid,
    String targetGroupUuid,
  ) async {
    await _bridge.call('move_entry', [handle, entryUuid, targetGroupUuid]);
  }

  @override
  Future<String> createGroup(int handle, String parentUuid, String name) async {
    final result =
        await _bridge.call('create_group', [handle, parentUuid, name]);
    final json = jsonDecode(result) as Map<String, dynamic>;
    return json['uuid'] as String;
  }

  @override
  Future<void> renameGroup(int handle, String groupUuid, String name) async {
    await _bridge.call('rename_group', [handle, groupUuid, name]);
  }

  @override
  Future<void> deleteGroup(int handle, String groupUuid) async {
    await _bridge.call('delete_group', [handle, groupUuid]);
  }

  @override
  Future<void> moveGroup(
    int handle,
    String groupUuid,
    String targetParentUuid,
  ) async {
    await _bridge.call('move_group', [handle, groupUuid, targetParentUuid]);
  }

  @override
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

  @override
  Future<Map<String, dynamic>?> getTotpCode(int handle, String entryUuid) {
    return _bridge.call('get_totp', [handle, entryUuid]).then((result) {
      final decoded = jsonDecode(result);
      if (decoded == null) {
        return null;
      }
      return Map<String, dynamic>.from(decoded as Map<String, dynamic>);
    });
  }

  @override
  Future<Map<String, dynamic>> mergeDatabases(int handleA, int handleB) async {
    final result = await _bridge.call('merge_databases', [handleA, handleB]);
    return jsonDecode(result) as Map<String, dynamic>;
  }

  Future<String> extractChallenge(List<int> dbBytes) async {
    return await _bridge.call('extract_challenge', [
      Uint8List.fromList(dbBytes),
    ]);
  }

  @override
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
