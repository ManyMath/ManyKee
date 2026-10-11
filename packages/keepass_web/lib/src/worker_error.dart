class KeePassWebError implements Exception {
  final String code;
  final String message;

  KeePassWebError(this.code, this.message);

  @override
  String toString() => 'KeePassWebError($code): $message';
}
