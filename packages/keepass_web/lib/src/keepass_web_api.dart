import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:keepass/src/keepass_api.dart';
import 'worker_bridge.dart';

/// Web implementation of [KeePassApi] using WASM Worker bridge.
///
/// All database operations are dispatched to a Web Worker running
/// the keepassxc-wasm module via postMessage RPC (D-09).
class KeePassWebApi implements KeePassApi {
  final WorkerBridge _bridge = WorkerBridge();

  @override
  Stream<int> get progress => _bridge.progress;

  @override
  Future<void> init() => _bridge.init();

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
    final result =
        await _bridge.call('open_db_with_challenge_response', [
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
    final result =
        await _bridge.call('read_entry_fields', [handle, entryUuid]);
    return jsonDecode(result) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> mergeDatabases(
      int handleA, int handleB) async {
    final result =
        await _bridge.call('merge_databases', [handleA, handleB]);
    return jsonDecode(result) as Map<String, dynamic>;
  }

  @override
  Future<void> dispose() async {
    _bridge.dispose();
  }
}
