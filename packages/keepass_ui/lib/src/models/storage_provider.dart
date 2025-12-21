import 'dart:typed_data';

abstract class StorageProvider {
  Future<List<StorageItem>> list();

  Future<StorageOpenResult> open();

  Future<void> save(Uint8List bytes, {required String name});
}

class StorageItem {
  const StorageItem({
    required this.name,
    this.lastModified,
    this.path,
  });

  final String name;
  final DateTime? lastModified;
  final String? path;
}

class StorageOpenResult {
  const StorageOpenResult({
    required this.bytes,
    required this.name,
  });

  final Uint8List bytes;
  final String name;
}

sealed class StorageError implements Exception {
  const StorageError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class StorageNotFoundError extends StorageError {
  const StorageNotFoundError([super.message = 'Storage item not found']);
}

class StoragePermissionDeniedError extends StorageError {
  const StoragePermissionDeniedError([
    super.message = 'Storage permission denied',
  ]);
}

class StorageProviderUnavailableError extends StorageError {
  const StorageProviderUnavailableError([
    super.message = 'Storage provider unavailable',
  ]);
}
