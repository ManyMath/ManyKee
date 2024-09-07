/// Error thrown when a KeePass FFI operation fails.
class KeePassError implements Exception {
  final int code;
  final String message;

  KeePassError(this.code, this.message);

  @override
  String toString() => 'KeePassError($code): $message';
}
