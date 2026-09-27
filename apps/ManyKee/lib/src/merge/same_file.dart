import 'dart:io';

/// Canonical form of [path] for "is this the same file?" comparisons.
///
/// Resolves symlinks and `..`/`.` segments. The file itself need not exist
/// yet (a save-as destination usually doesn't): in that case the parent
/// directory is resolved and the file name re-appended.
String canonicalFilePath(String path) {
  final file = File(path);
  try {
    return file.resolveSymbolicLinksSync();
  } on FileSystemException {
    final parent = file.parent;
    String parentPath;
    try {
      parentPath = parent.resolveSymbolicLinksSync();
    } on FileSystemException {
      parentPath = parent.absolute.path;
    }
    final name = file.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (parentPath.endsWith(Platform.pathSeparator)) {
      return '$parentPath$name';
    }
    return '$parentPath${Platform.pathSeparator}$name';
  }
}

/// Whether [a] and [b] refer to the same file on disk, after canonicalising
/// both (see [canonicalFilePath]).
bool pathsReferToSameFile(String a, String b) =>
    canonicalFilePath(a) == canonicalFilePath(b);
