import 'dart:io';

import 'package:keepass/keepass.dart';
export 'package:keepass/keepass.dart' show MergeResult;

MergeService createMergeService() => _NativeMergeService();

/// Result of a full merge-and-save: the [MergeResult] counts plus the path
/// the merged database was written to.
class MergeServiceResult {
  MergeServiceResult({required this.mergeResult, required this.outputPath});

  final MergeResult mergeResult;
  final String outputPath;
}

/// Opens two KDBX databases independently, merges the second into the
/// first, and saves the result to a new file.
///
/// Every step here is a direct (blocking) FFI call via `package:keepass`'s
/// `Database`, matching `packages/keepass_cli/lib/src/merge_command.dart`.
/// Safety is enforced by construction, not by convention: [openA] and
/// [openB] are the *only* way to obtain the opened-database handles this
/// class will merge, and each independently proves its database decrypts
/// before it is held onto. There is no code path that reaches [merge]
/// without both opens having already succeeded.
abstract class MergeService {
  /// Opens source database A. Throws [KeePassError] if it fails to
  /// open/decrypt: callers must not treat A as mergeable unless this
  /// returns normally.
  Future<void> openA({
    required String filePath,
    required String password,
  });

  /// Opens source database B, independently of [openA]. Throws
  /// [KeePassError] if it fails to open/decrypt.
  Future<void> openB({
    required String filePath,
    required String password,
  });

  /// Whether both [openA] and [openB] have completed successfully. The
  /// merge preview/confirmation UI should not be reachable until this is
  /// true.
  bool get bothOpen;

  /// Merges B into A and returns the counts, without writing anything to
  /// disk yet. Requires [bothOpen].
  MergeResult preview();

  /// Merges B into A (if not already merged via [preview]) and saves the
  /// result to a new file at [outputPath] using [outputPassword]. Requires
  /// [bothOpen].
  MergeServiceResult saveMergedCopy({
    required String outputPath,
    required String outputPassword,
  });

  /// Releases native resources. Safe to call multiple times and at any
  /// point (partial progress included).
  void dispose();
}

class _NativeMergeService implements MergeService {
  Database? _dbA;
  Database? _dbB;
  MergeResult? _cachedResult;

  @override
  bool get bothOpen => _dbA != null && _dbB != null;

  @override
  Future<void> openA({
    required String filePath,
    required String password,
  }) async {
    if (!File(filePath).existsSync()) {
      throw KeePassError.fromCode('FILE_NOT_FOUND', 'File not found: $filePath');
    }
    _dbA?.close();
    _dbA = Database.open(filePath, password: password);
  }

  @override
  Future<void> openB({
    required String filePath,
    required String password,
  }) async {
    if (!File(filePath).existsSync()) {
      throw KeePassError.fromCode('FILE_NOT_FOUND', 'File not found: $filePath');
    }
    _dbB?.close();
    _dbB = Database.open(filePath, password: password);
  }

  @override
  MergeResult preview() {
    final a = _dbA;
    final b = _dbB;
    if (a == null || b == null) {
      throw StateError(
          'Both databases must be opened successfully before merging.');
    }
    return _cachedResult ??= a.merge(b);
  }

  @override
  MergeServiceResult saveMergedCopy({
    required String outputPath,
    required String outputPassword,
  }) {
    final a = _dbA;
    if (a == null || _dbB == null) {
      throw StateError(
          'Both databases must be opened successfully before merging.');
    }
    final result = preview();
    a.save(outputPath, password: outputPassword);
    return MergeServiceResult(mergeResult: result, outputPath: outputPath);
  }

  @override
  void dispose() {
    _dbA?.close();
    _dbB?.close();
    _dbA = null;
    _dbB = null;
    _cachedResult = null;
  }
}
