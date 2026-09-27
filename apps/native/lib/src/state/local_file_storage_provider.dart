import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:keepass_ui/keepass_ui.dart';

import 'atomic_file_write.dart';

class LocalFileStorageProvider implements StorageProvider {
  LocalFileStorageProvider({String? initialPath}) : _currentPath = initialPath;

  String? _currentPath;

  String? get currentPath => _currentPath;

  void rememberPath(String? path) {
    _currentPath = path;
  }

  @override
  Future<List<StorageItem>> list() async {
    final path = _currentPath;
    if (path == null) {
      return const <StorageItem>[];
    }

    final file = File(path);
    if (!await file.exists()) {
      return const <StorageItem>[];
    }

    final stat = await file.stat();
    return <StorageItem>[
      StorageItem(
        name: file.uri.pathSegments.isEmpty ? path : file.uri.pathSegments.last,
        lastModified: stat.modified,
        path: path,
      ),
    ];
  }

  @override
  Future<StorageOpenResult> open() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['kdbx'],
      dialogTitle: 'Choose KDBX File',
    );
    final picked =
        result?.files.isNotEmpty == true ? result!.files.single : null;
    final path = picked?.path;
    if (picked == null || path == null) {
      throw const StorageProviderUnavailableError('No file selected');
    }

    try {
      final bytes = await File(path).readAsBytes();
      _currentPath = path;
      return StorageOpenResult(bytes: bytes, name: picked.name);
    } on FileSystemException catch (error) {
      throw _mapFileError(error);
    }
  }

  @override
  Future<void> save(Uint8List bytes, {required String name}) async {
    final path = _currentPath;
    if (path == null) {
      throw const StorageNotFoundError('No file path is available for save');
    }

    try {
      await writeFileAtomically(path, bytes);
    } on FileSystemException catch (error) {
      throw _mapFileError(error);
    }
  }

  StorageError _mapFileError(FileSystemException error) {
    final message = error.message.toLowerCase();
    if (message.contains('permission') || message.contains('denied')) {
      return StoragePermissionDeniedError(error.message);
    }
    if (message.contains('not found') || message.contains('no such file')) {
      return StorageNotFoundError(error.message);
    }
    return StorageProviderUnavailableError(error.message);
  }
}
