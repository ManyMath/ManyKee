import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'bindings.g.dart';
import 'error.dart';
import 'ffi_helpers.dart';
import 'group.dart';
import 'merge_result.dart';
import 'native_library.dart';

/// A KeePass KDBX database.
///
/// Wraps a native Rust database handle. Resources are freed automatically
/// by the garbage collector, or explicitly by calling [close].
class Database implements Finalizable {
  static final _finalizer = NativeFinalizer(
    nativeLibrary
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>(
            'kpxc_database_free')
        .cast(),
  );

  final Pointer<KpxcDatabase> _handle;
  bool _closed = false;

  Database._(this._handle) {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Database is closed');
  }

  /// The raw native handle. For internal use by Entry/Group/merge operations.
  Pointer<KpxcDatabase> get handle {
    _ensureOpen();
    return _handle;
  }

  /// Open a KDBX database with a password.
  factory Database.open(String path, {required String password}) {
    final pathPtr = toNativeString(path);
    final passPtr = toNativeString(password);
    try {
      final handle = bindings.kpxc_database_open(pathPtr, passPtr);
      if (handle == nullptr) {
        throw KeePassError.fromLastError('Failed to open database');
      }
      return Database._(handle);
    } finally {
      malloc.free(pathPtr);
      malloc.free(passPtr);
    }
  }

  factory Database.openWithKeyFile(
    String path, {
    required String password,
    required String keyFilePath,
  }) {
    final pathPtr = toNativeString(path);
    final passPtr = toNativeString(password);
    final keyPtr = toNativeString(keyFilePath);
    try {
      final handle =
          bindings.kpxc_database_open_with_keyfile(pathPtr, passPtr, keyPtr);
      if (handle == nullptr) {
        throw KeePassError.fromLastError(
            'Failed to open database with key file');
      }
      return Database._(handle);
    } finally {
      malloc.free(pathPtr);
      malloc.free(passPtr);
      malloc.free(keyPtr);
    }
  }

  /// Save the database to a file.
  void save(String path, {required String password}) {
    _ensureOpen();
    final pathPtr = toNativeString(path);
    final passPtr = toNativeString(password);
    try {
      final result = bindings.kpxc_database_save(_handle, pathPtr, passPtr);
      KeePassError.checkResult(result, 'Failed to save database');
    } finally {
      malloc.free(pathPtr);
      malloc.free(passPtr);
    }
  }

  /// Save the database using a password + key file composite key.
  void saveWithKeyFile(
    String path, {
    required String password,
    required String keyFilePath,
  }) {
    _ensureOpen();
    final pathPtr = toNativeString(path);
    final passPtr = toNativeString(password);
    final keyPtr = toNativeString(keyFilePath);
    try {
      final result = bindings.kpxc_database_save_with_keyfile(
        _handle,
        pathPtr,
        passPtr,
        keyPtr,
      );
      KeePassError.checkResult(result, 'Failed to save database with key file');
    } finally {
      malloc.free(pathPtr);
      malloc.free(passPtr);
      malloc.free(keyPtr);
    }
  }

  /// Save the database to a temporary file and return its bytes.
  List<int> saveBytes({
    required String password,
    List<int>? keyFileBytes,
  }) {
    _ensureOpen();
    final tempDir = Directory.systemTemp;
    final tempPath =
        '${tempDir.path}/manykee_save_${DateTime.now().microsecondsSinceEpoch}.kdbx';
    final tempFile = File(tempPath);

    File? tempKeyFile;
    try {
      if (keyFileBytes != null) {
        final keyPath =
            '${tempDir.path}/manykee_save_${DateTime.now().microsecondsSinceEpoch}.key';
        tempKeyFile = File(keyPath);
        tempKeyFile.writeAsBytesSync(keyFileBytes, flush: true);
        saveWithKeyFile(
          tempFile.path,
          password: password,
          keyFilePath: tempKeyFile.path,
        );
      } else {
        save(tempFile.path, password: password);
      }
      return tempFile.readAsBytesSync();
    } finally {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      if (tempKeyFile != null && tempKeyFile.existsSync()) {
        tempKeyFile.deleteSync();
      }
    }
  }

  /// Get the root group of the database.
  Group get rootGroup {
    _ensureOpen();
    final uuidStr = readAndFreeStringOrThrow(
      bindings.kpxc_database_root_uuid(_handle),
      'Failed to get root group UUID',
    );
    return Group(this, uuidStr);
  }

  /// Merge another database into this one.
  /// Returns a [MergeResult] with counts and details.
  MergeResult merge(Database other) {
    _ensureOpen();
    other._ensureOpen();
    final jsonPtr = bindings.kpxc_database_merge(_handle, other._handle);
    if (jsonPtr == nullptr) {
      throw KeePassError.fromLastError('Merge failed');
    }
    final jsonStr = readAndFreeString(jsonPtr)!;
    return MergeResult.fromJson(json.decode(jsonStr) as Map<String, dynamic>);
  }

  factory Database.openWithYubiKey(
    String path, {
    required String password,
    required String slot,
    int serial = 0,
  }) {
    final pathPtr = toNativeString(path);
    final passPtr = toNativeString(password);
    final slotPtr = toNativeString(slot);
    try {
      final handle = bindings.kpxc_database_open_with_yubikey(
        pathPtr,
        passPtr,
        slotPtr,
        serial,
      );
      if (handle == nullptr) {
        throw KeePassError.fromLastError('Failed to open with YubiKey');
      }
      return Database._(handle);
    } finally {
      malloc.free(pathPtr);
      malloc.free(passPtr);
      malloc.free(slotPtr);
    }
  }

  static List<Map<String, dynamic>> listYubiKeys() {
    final jsonPtr = bindings.kpxc_yubikey_list();
    if (jsonPtr == nullptr) {
      // No YubiKeys found or enumeration not supported — return empty.
      return [];
    }
    final jsonStr = readAndFreeString(jsonPtr);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    return (json.decode(jsonStr) as List).cast<Map<String, dynamic>>();
  }

  /// Explicitly close and free native resources.
  void close() {
    if (!_closed) {
      _finalizer.detach(this);
      bindings.kpxc_database_free(_handle);
      _closed = true;
    }
  }
}
