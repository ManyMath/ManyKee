import 'dart:async';
import 'package:keepass/src/keepass_api.dart';

/// Web implementation of [KeePassApi] using WASM Worker bridge.
///
/// Communicates with a Web Worker running the keepassxc-wasm module
/// via postMessage RPC (D-09).
class KeePassWebApi implements KeePassApi {
  final _progressController = StreamController<int>.broadcast();

  @override
  Stream<int> get progress => _progressController.stream;

  @override
  Future<void> init() async {
    // TODO(plan-04): Initialize Worker, load WASM module, await ready
    throw UnimplementedError('KeePassWebApi.init() not yet implemented');
  }

  @override
  Future<int> openDatabase(List<int> dbBytes,
      {required String password}) async {
    throw UnimplementedError('KeePassWebApi.openDatabase() not yet implemented');
  }

  @override
  Future<int> openDatabaseWithKeyFile(
    List<int> dbBytes, {
    required String password,
    required List<int> keyFileBytes,
  }) async {
    throw UnimplementedError(
        'KeePassWebApi.openDatabaseWithKeyFile() not yet implemented');
  }

  @override
  Future<int> openDatabaseWithChallengeResponse(
    List<int> dbBytes, {
    required String password,
    required String challengeResponseHex,
  }) async {
    throw UnimplementedError(
        'KeePassWebApi.openDatabaseWithChallengeResponse() not yet implemented');
  }

  @override
  Future<void> closeDatabase(int handle) async {
    throw UnimplementedError(
        'KeePassWebApi.closeDatabase() not yet implemented');
  }

  @override
  Future<List<Map<String, dynamic>>> listGroups(
      int handle, String groupUuid) async {
    throw UnimplementedError(
        'KeePassWebApi.listGroups() not yet implemented');
  }

  @override
  Future<List<Map<String, dynamic>>> listEntries(
      int handle, String groupUuid) async {
    throw UnimplementedError(
        'KeePassWebApi.listEntries() not yet implemented');
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(
      int handle, String entryUuid) async {
    throw UnimplementedError(
        'KeePassWebApi.readEntryFields() not yet implemented');
  }

  @override
  Future<Map<String, dynamic>> mergeDatabases(int handleA, int handleB) async {
    throw UnimplementedError(
        'KeePassWebApi.mergeDatabases() not yet implemented');
  }

  @override
  Future<void> dispose() async {
    await _progressController.close();
  }
}
