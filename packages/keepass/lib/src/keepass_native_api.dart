import 'dart:async';
import 'dart:io';

import 'database.dart';
import 'entry.dart';
import 'group.dart';
import 'keepass_api.dart';

/// Native FFI implementation of [KeePassApi].
///
/// Wraps the FFI [Database], [Group], and [Entry] classes.
/// Manages database handles via an int-keyed map.
class KeePassNativeApi implements KeePassApi {
  final Map<int, Database> _databases = {};
  int _nextHandle = 1;
  final StreamController<int> _progressController =
      StreamController<int>.broadcast();

  int _registerHandle(Database db) {
    final handle = _nextHandle++;
    _databases[handle] = db;
    return handle;
  }

  Database _getDb(int handle) {
    final db = _databases[handle];
    if (db == null) throw StateError('Invalid database handle: $handle');
    return db;
  }

  @override
  Stream<int> get progress => _progressController.stream;

  @override
  Future<void> init() async {
    // No-op for native -- FFI is always available.
  }

  @override
  Future<int> openDatabase(List<int> dbBytes,
      {required String password}) async {
    // Temp file bridge: write bytes to temp file, open via FFI, delete temp file.
    final tempFile = await _writeTempFile(dbBytes);
    try {
      _progressController.add(-1); // Indeterminate progress
      final db = await Future.delayed(
          Duration.zero, () => Database.open(tempFile.path, password: password));
      _progressController.add(100);
      return _registerHandle(db);
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  @override
  Future<int> openDatabaseWithKeyFile(
    List<int> dbBytes, {
    required String password,
    required List<int> keyFileBytes,
  }) async {
    final tempDbFile = await _writeTempFile(dbBytes);
    final tempKeyFile = await _writeTempFile(keyFileBytes, suffix: '.key');
    try {
      _progressController.add(-1);
      final db = await Future.delayed(
          Duration.zero,
          () => Database.openWithKeyFile(tempDbFile.path,
              password: password, keyFilePath: tempKeyFile.path));
      _progressController.add(100);
      return _registerHandle(db);
    } finally {
      try {
        await tempDbFile.delete();
      } catch (_) {}
      try {
        await tempKeyFile.delete();
      } catch (_) {}
    }
  }

  @override
  Future<int> openDatabaseWithChallengeResponse(
    List<int> dbBytes, {
    required String password,
    required String challengeResponseHex,
  }) async {
    // Challenge-response is pre-computed -- pass as password+challenge.
    // The FFI Database does not currently support challenge-response directly.
    // For now, throw UnsupportedError -- YubiKey native support is Phase 9 (YUBI-01).
    throw UnsupportedError(
      'Challenge-response not yet supported on native. '
      'Use KeePassWebApi for YubiKey.',
    );
  }

  @override
  Future<void> closeDatabase(int handle) async {
    final db = _databases.remove(handle);
    db?.close();
  }

  @override
  Future<List<Map<String, dynamic>>> listGroups(
      int handle, String groupUuid) async {
    final db = _getDb(handle);
    final List<Group> children;
    if (groupUuid.isEmpty) {
      // Root group's children
      final root = db.rootGroup;
      children = root.groups;
    } else {
      children = Group(db, groupUuid).groups;
    }
    return children
        .map((g) => <String, dynamic>{
              'uuid': g.uuid,
              'name': g.name,
            })
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> listEntries(
      int handle, String groupUuid) async {
    final db = _getDb(handle);
    final List<Entry> entries;
    if (groupUuid.isEmpty) {
      entries = db.rootGroup.entries;
    } else {
      entries = Group(db, groupUuid).entries;
    }
    return entries
        .map((e) => <String, dynamic>{
              'uuid': e.uuid,
              'title': e.title ?? '',
              'username': e.userName ?? '',
              'url': e.url ?? '',
            })
        .toList();
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(
      int handle, String entryUuid) async {
    final db = _getDb(handle);
    final entry = Entry(db, entryUuid);
    // Read standard fields. getField returns null for missing fields.
    final fields = <String, dynamic>{
      'Title': entry.title ?? '',
      'UserName': entry.userName ?? '',
      'Password': entry.password ?? '',
      'URL': entry.url ?? '',
      'Notes': entry.notes ?? '',
    };
    // TODO: Read custom fields when FFI supports field enumeration
    return fields;
  }

  @override
  Future<Map<String, dynamic>> mergeDatabases(
      int handleA, int handleB) async {
    final dbA = _getDb(handleA);
    final dbB = _getDb(handleB);
    final result = dbA.merge(dbB);
    return result.toJson();
  }

  /// Convenience method for native callers that already have a file path.
  /// Bypasses the bytes-to-tempfile roundtrip.
  Future<int> openFromPath(String filePath, {required String password}) async {
    _progressController.add(-1);
    final db = await Future.delayed(Duration.zero,
        () => Database.open(filePath, password: password));
    _progressController.add(100);
    return _registerHandle(db);
  }

  /// Convenience method for native callers with file path + key file path.
  Future<int> openFromPathWithKeyFile(
    String filePath, {
    required String password,
    required String keyFilePath,
  }) async {
    _progressController.add(-1);
    final db = await Future.delayed(
        Duration.zero,
        () => Database.openWithKeyFile(filePath,
            password: password, keyFilePath: keyFilePath));
    _progressController.add(100);
    return _registerHandle(db);
  }

  @override
  Future<void> dispose() async {
    for (final db in _databases.values) {
      db.close();
    }
    _databases.clear();
    await _progressController.close();
  }

  /// Write bytes to a temporary file for FFI bridging.
  Future<File> _writeTempFile(List<int> bytes,
      {String suffix = '.kdbx'}) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      '${tempDir.path}/manykee_${DateTime.now().millisecondsSinceEpoch}$suffix',
    );
    await tempFile.writeAsBytes(bytes);
    return tempFile;
  }
}
