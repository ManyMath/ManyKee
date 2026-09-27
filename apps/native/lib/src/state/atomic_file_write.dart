import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Replaces the file at [path] with [bytes] without ever leaving a truncated
/// or half-written file there.
///
/// The bytes go to a hidden sibling temp file (`.<name>.<random>.tmp`) that
/// is flushed and then renamed over [path], so a crash or a full disk
/// mid-write leaves the original intact; the temp file is deleted on
/// failure. When [path] already exists the temp file starts out as a copy
/// of it, which carries over its permission bits (Dart has no chmod).
/// Symlinks are resolved first so the link itself is kept.
///
/// If the directory does not allow creating a sibling file at all (e.g. a
/// sandboxed macOS app that was only granted the vault file itself), this
/// falls back to writing [path] in place.
Future<void> writeFileAtomically(
  String path,
  List<int> bytes, {
  @visibleForTesting
  Future<void> Function(File file, List<int> bytes) writeBytes = _writeAndFlush,
}) async {
  final target = File(await _resolveLinks(path));
  final temp = File(_tempPathFor(target));

  try {
    if (await target.exists()) {
      await target.copy(temp.path);
    } else {
      await temp.create(exclusive: true);
    }
  } on FileSystemException catch (error) {
    await _deleteQuietly(temp);
    if (!_isPermissionDenied(error)) rethrow;
    await writeBytes(target, bytes);
    return;
  }

  try {
    await writeBytes(temp, bytes);
    await temp.rename(target.path);
  } catch (_) {
    await _deleteQuietly(temp);
    rethrow;
  }
}

Future<void> _writeAndFlush(File file, List<int> bytes) =>
    file.writeAsBytes(bytes, flush: true);

Future<String> _resolveLinks(String path) async {
  if (!await FileSystemEntity.isLink(path)) return path;
  try {
    return await File(path).resolveSymbolicLinks();
  } on FileSystemException {
    return path;
  }
}

final Random _random = Random();

String _tempPathFor(File target) {
  final segments = target.uri.pathSegments;
  final name = segments.isEmpty ? 'vault' : segments.last;
  final suffix = _random.nextInt(1 << 32).toRadixString(16);
  return '${target.parent.path}${Platform.pathSeparator}.$name.$suffix.tmp';
}

bool _isPermissionDenied(FileSystemException error) {
  final code = error.osError?.errorCode;
  if (Platform.isWindows) return code == 5; // ERROR_ACCESS_DENIED
  return code == 1 || code == 13; // EPERM, EACCES
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on FileSystemException {
    // Best effort; a stray hidden temp file is harmless.
  }
}
