import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'bindings.g.dart';
import 'native_library.dart';

final KeePassXcFfiBindings _errorBindings = KeePassXcFfiBindings(nativeLibrary);

/// Reads the thread-local `kpxc_last_error()` message, or null when the
/// native layer has not recorded one since its last successful call.
String? readLastNativeErrorMessage() {
  final msgPtr = _errorBindings.kpxc_last_error();
  if (msgPtr == nullptr) {
    return null;
  }
  return msgPtr.cast<Utf8>().toDartString();
}

/// Error thrown when a KeePass FFI operation fails.
class KeePassError implements Exception {
  /// Status code of the failed native call. One of the `KPXC_ERR_*` values
  /// below for calls that return a status; [unknownCode] for calls that
  /// signal failure with a null pointer and for errors raised on the Dart
  /// side (see [KeePassError.fromCode]).
  final int code;
  final String message;

  /// Code reported when the failing call carries no numeric status.
  static const int unknownCode = -1;

  // Status codes returned by the Rust FFI layer.
  static const int ioError = KPXC_ERR_IO;
  static const int openError = KPXC_ERR_OPEN;
  static const int saveError = KPXC_ERR_SAVE;
  static const int notFound = KPXC_ERR_NOT_FOUND;
  static const int mergeError = KPXC_ERR_MERGE;
  static const int yubiKeyError = KPXC_ERR_YUBIKEY;
  static const int nullPointer = KPXC_ERR_NULL_PTR;
  static const int invalidUtf8 = KPXC_ERR_INVALID_UTF8;
  static const int parseError = KPXC_ERR_PARSE;
  static const int panic = KPXC_ERR_PANIC;

  KeePassError(this.code, this.message);

  /// Builds an error from `kpxc_last_error()`, prefixed with [context].
  /// [code] is the status the failing call returned; leave it unset for
  /// calls that only return a null pointer on failure.
  factory KeePassError.fromLastError([
    String? context,
    int code = unknownCode,
  ]) {
    var message = readLastNativeErrorMessage() ?? context ?? 'Unknown error';
    if (context != null && message.isNotEmpty) {
      message = '$context: $message';
    }
    return KeePassError(code, message);
  }

  /// Throws when [code] is not `KPXC_OK`, carrying [code] and the native
  /// error message.
  static void checkResult(int code, [String? context]) {
    if (code != KPXC_OK) {
      throw KeePassError.fromLastError(context, code);
    }
  }

  factory KeePassError.fromCode(String code, String message) {
    return KeePassError(unknownCode, '[$code] $message');
  }

  @override
  String toString() => 'KeePassError($code): $message';
}
