import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'bindings.g.dart';
import 'native_library.dart';

/// Singleton bindings for error handling only.
/// This avoids a circular dependency with ffi_helpers.dart.
final KeePassXcFfiBindings _errorBindings = KeePassXcFfiBindings(nativeLibrary);

/// Error thrown when a KeePass FFI operation fails.
class KeePassError implements Exception {
  final int code;
  final String message;

  KeePassError(this.code, this.message);

  /// Create from the last FFI error.
  factory KeePassError.fromLastError([String? context]) {
    final msgPtr = _errorBindings.kpxc_last_error();
    String message;
    if (msgPtr == nullptr) {
      message = context ?? 'Unknown error';
    } else {
      message = msgPtr.cast<Utf8>().toDartString();
      // Do NOT free kpxc_last_error pointer -- it's owned by thread-local storage
    }
    if (context != null && message.isNotEmpty) {
      message = '$context: $message';
    }
    return KeePassError(-1, message);
  }

  /// Check an FFI return code and throw if non-zero.
  static void checkResult(int code, [String? context]) {
    if (code != 0) {
      throw KeePassError.fromLastError(context);
    }
  }

  @override
  String toString() => 'KeePassError($code): $message';
}
