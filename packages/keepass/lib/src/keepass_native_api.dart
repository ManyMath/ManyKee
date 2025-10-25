import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'database.dart';
import 'entry.dart';
import 'group.dart';
import 'error.dart';
import 'keepass_api.dart';

/// Native FFI implementation of [KeePassApi].
///
/// All database handles live inside a dedicated worker isolate so expensive
/// open/KDF work cannot block the Flutter UI isolate.
class KeePassNativeApi implements KeePassApi {
  final StreamController<int> _progressController =
      StreamController<int>.broadcast();
  Future<SendPort>? _workerPortFuture;

  @override
  Stream<int> get progress => _progressController.stream;

  @override
  Future<void> init() async {
    await _workerPort();
  }

  @override
  Future<int> openDatabase(
    List<int> dbBytes, {
    required String password,
  }) async {
    final tempFile = await _writeTempFile(dbBytes);
    try {
      return _openFromWorker(
        'openFromPath',
        <String, Object?>{
          'filePath': tempFile.path,
          'password': password,
        },
      );
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
      return _openFromWorker(
        'openFromPathWithKeyFile',
        <String, Object?>{
          'filePath': tempDbFile.path,
          'password': password,
          'keyFilePath': tempKeyFile.path,
        },
      );
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
    final tempFile = await _writeTempFile(dbBytes);
    try {
      return _openFromWorker(
        'openFromPathWithYubiKey',
        <String, Object?>{
          'filePath': tempFile.path,
          'password': password,
          'slot': '2',
        },
      );
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> closeDatabase(int handle) async {
    await _invoke('closeDatabase', <String, Object?>{'handle': handle});
  }

  @override
  Future<List<Map<String, dynamic>>> listGroups(
    int handle,
    String groupUuid,
  ) async {
    final result = await _invoke(
      'listGroups',
      <String, Object?>{
        'handle': handle,
        'groupUuid': groupUuid,
      },
    );
    return _castListOfMaps(result);
  }

  @override
  Future<List<Map<String, dynamic>>> listEntries(
    int handle,
    String groupUuid,
  ) async {
    final result = await _invoke(
      'listEntries',
      <String, Object?>{
        'handle': handle,
        'groupUuid': groupUuid,
      },
    );
    return _castListOfMaps(result);
  }

  @override
  Future<Map<String, dynamic>> readEntryFields(
    int handle,
    String entryUuid,
  ) async {
    final result = await _invoke(
      'readEntryFields',
      <String, Object?>{
        'handle': handle,
        'entryUuid': entryUuid,
      },
    );
    return _castMap(result);
  }

  @override
  Future<Map<String, dynamic>> mergeDatabases(int handleA, int handleB) async {
    final result = await _invoke(
      'mergeDatabases',
      <String, Object?>{
        'handleA': handleA,
        'handleB': handleB,
      },
    );
    return _castMap(result);
  }

  Future<int> openFromPath(
    String filePath, {
    required String password,
  }) async {
    return _openFromWorker(
      'openFromPath',
      <String, Object?>{
        'filePath': filePath,
        'password': password,
      },
    );
  }

  Future<int> openFromPathWithKeyFile(
    String filePath, {
    required String password,
    required String keyFilePath,
  }) async {
    return _openFromWorker(
      'openFromPathWithKeyFile',
      <String, Object?>{
        'filePath': filePath,
        'password': password,
        'keyFilePath': keyFilePath,
      },
    );
  }

  Future<int> openFromPathWithYubiKey(
    String filePath, {
    required String password,
    required String slot,
    int serial = 0,
  }) async {
    return _openFromWorker(
      'openFromPathWithYubiKey',
      <String, Object?>{
        'filePath': filePath,
        'password': password,
        'slot': slot,
        'serial': serial,
      },
    );
  }

  Future<List<Map<String, dynamic>>> listYubiKeys() async {
    final result = await _invoke('listYubiKeys');
    return _castListOfMaps(result);
  }

  @override
  Future<void> dispose() async {
    if (_workerPortFuture != null) {
      try {
        await _invoke('shutdown');
      } catch (_) {}
    }
    await _progressController.close();
  }

  Future<File> _writeTempFile(
    List<int> bytes, {
    String suffix = '.kdbx',
  }) async {
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      '${tempDir.path}/manykee_${DateTime.now().millisecondsSinceEpoch}$suffix',
    );
    await tempFile.writeAsBytes(bytes);
    return tempFile;
  }

  Future<int> _openFromWorker(
    String method,
    Map<String, Object?> args,
  ) async {
    _progressController.add(-1);
    try {
      final result = await _invoke(method, args);
      return result as int;
    } finally {
      _progressController.add(100);
    }
  }

  Future<dynamic> _invoke(
    String method, [
    Map<String, Object?> args = const <String, Object?>{},
  ]) async {
    final workerPort = await _workerPort();
    final replyPort = ReceivePort();
    workerPort.send(<String, Object?>{
      'method': method,
      'args': args,
      'replyPort': replyPort.sendPort,
    });

    try {
      final response = Map<String, Object?>.from(
        await replyPort.first as Map,
      );
      final ok = response['ok'] == true;
      if (!ok) {
        throw KeePassError.fromCode(
          'NATIVE_WORKER',
          response['error'] as String? ?? 'Unknown native worker error',
        );
      }
      return response['result'];
    } finally {
      replyPort.close();
    }
  }

  Future<SendPort> _workerPort() {
    return _workerPortFuture ??= _spawnWorker();
  }

  Future<SendPort> _spawnWorker() async {
    final readyPort = ReceivePort();
    await Isolate.spawn(_nativeWorkerMain, readyPort.sendPort);
    return await readyPort.first as SendPort;
  }
}

Future<void> _nativeWorkerMain(SendPort readyPort) async {
  final receivePort = ReceivePort();
  readyPort.send(receivePort.sendPort);

  final databases = <int, Database>{};
  var nextHandle = 1;

  try {
    await for (final rawMessage in receivePort) {
      if (rawMessage is! Map) {
        continue;
      }

      final message = Map<String, Object?>.from(rawMessage);
      final replyPort = message['replyPort'] as SendPort;
      final method = message['method'] as String;
      final args = Map<String, Object?>.from(
        (message['args'] as Map?) ?? const <String, Object?>{},
      );

      try {
        final result = switch (method) {
          'openFromPath' => _workerOpenFromPath(databases, nextHandle++, args),
          'openFromPathWithKeyFile' =>
            _workerOpenFromPathWithKeyFile(databases, nextHandle++, args),
          'openFromPathWithYubiKey' =>
            _workerOpenFromPathWithYubiKey(databases, nextHandle++, args),
          'closeDatabase' => _workerCloseDatabase(databases, args),
          'listGroups' => _workerListGroups(databases, args),
          'listEntries' => _workerListEntries(databases, args),
          'readEntryFields' => _workerReadEntryFields(databases, args),
          'mergeDatabases' => _workerMergeDatabases(databases, args),
          'listYubiKeys' => Database.listYubiKeys(),
          'shutdown' => null,
          _ => throw StateError('Unknown native worker method: $method'),
        };

        replyPort.send(<String, Object?>{'ok': true, 'result': result});

        if (method == 'shutdown') {
          receivePort.close();
          break;
        }
      } on KeePassError catch (error) {
        replyPort.send(<String, Object?>{'ok': false, 'error': error.message});
      } catch (error) {
        replyPort
            .send(<String, Object?>{'ok': false, 'error': error.toString()});
      }
    }
  } finally {
    for (final database in databases.values) {
      database.close();
    }
  }
}

int _workerOpenFromPath(
  Map<int, Database> databases,
  int handle,
  Map<String, Object?> args,
) {
  final database = Database.open(
    args['filePath']! as String,
    password: args['password']! as String,
  );
  databases[handle] = database;
  return handle;
}

int _workerOpenFromPathWithKeyFile(
  Map<int, Database> databases,
  int handle,
  Map<String, Object?> args,
) {
  final database = Database.openWithKeyFile(
    args['filePath']! as String,
    password: args['password']! as String,
    keyFilePath: args['keyFilePath']! as String,
  );
  databases[handle] = database;
  return handle;
}

int _workerOpenFromPathWithYubiKey(
  Map<int, Database> databases,
  int handle,
  Map<String, Object?> args,
) {
  final database = Database.openWithYubiKey(
    args['filePath']! as String,
    password: args['password']! as String,
    slot: args['slot']! as String,
    serial: args['serial'] as int? ?? 0,
  );
  databases[handle] = database;
  return handle;
}

Object? _workerCloseDatabase(
  Map<int, Database> databases,
  Map<String, Object?> args,
) {
  final handle = args['handle']! as int;
  final database = databases.remove(handle);
  if (database == null) {
    throw StateError('Invalid database handle: $handle');
  }
  database.close();
  return null;
}

List<Map<String, dynamic>> _workerListGroups(
  Map<int, Database> databases,
  Map<String, Object?> args,
) {
  final database = _workerGetDatabase(databases, args['handle']! as int);
  final groupUuid = args['groupUuid']! as String;
  final children = groupUuid.isEmpty
      ? database.rootGroup.groups
      : Group(database, groupUuid).groups;
  return children
      .map(
        (group) => <String, dynamic>{
          'uuid': group.uuid,
          'name': group.name,
        },
      )
      .toList();
}

List<Map<String, dynamic>> _workerListEntries(
  Map<int, Database> databases,
  Map<String, Object?> args,
) {
  final database = _workerGetDatabase(databases, args['handle']! as int);
  final groupUuid = args['groupUuid']! as String;
  final entries = groupUuid.isEmpty
      ? database.rootGroup.entries
      : Group(database, groupUuid).entries;
  return entries
      .map(
        (entry) => <String, dynamic>{
          'uuid': entry.uuid,
          'title': entry.title ?? '',
          'username': entry.userName ?? '',
          'url': entry.url ?? '',
        },
      )
      .toList();
}

Map<String, dynamic> _workerReadEntryFields(
  Map<int, Database> databases,
  Map<String, Object?> args,
) {
  final database = _workerGetDatabase(databases, args['handle']! as int);
  final entry = Entry(database, args['entryUuid']! as String);
  return <String, dynamic>{
    'Title': entry.title ?? '',
    'UserName': entry.userName ?? '',
    'Password': entry.password ?? '',
    'URL': entry.url ?? '',
    'Notes': entry.notes ?? '',
  };
}

Map<String, dynamic> _workerMergeDatabases(
  Map<int, Database> databases,
  Map<String, Object?> args,
) {
  final databaseA = _workerGetDatabase(databases, args['handleA']! as int);
  final databaseB = _workerGetDatabase(databases, args['handleB']! as int);
  return databaseA.merge(databaseB).toJson();
}

Database _workerGetDatabase(Map<int, Database> databases, int handle) {
  final database = databases[handle];
  if (database == null) {
    throw StateError('Invalid database handle: $handle');
  }
  return database;
}

List<Map<String, dynamic>> _castListOfMaps(dynamic value) {
  final list = (value as List).cast<Map>();
  return list
      .map((item) => Map<String, dynamic>.from(item.cast<String, dynamic>()))
      .toList();
}

Map<String, dynamic> _castMap(dynamic value) {
  return Map<String, dynamic>.from((value as Map).cast<String, dynamic>());
}
