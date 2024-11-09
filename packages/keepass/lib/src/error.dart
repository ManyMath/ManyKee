import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'bindings.g.dart';
import 'native_library.dart';

final KeePassXcFfiBindings _errorBindings = KeePassXcFfiBindings(nativeLibrary);

/// Error thrown when a KeePass FFI operation fails.
class KeePassError implements Exception {
 final int code;
 final String message;

 KeePassError(this.code, this.message);

 factory KeePassError.fromLastError([String? context]) {
 final msgPtr = _errorBindings.kpxc_last_error();
 String message;
 if (msgPtr == nullptr) {
 message = context ?? 'Unknown error';
 } else {
 message = msgPtr.cast<Utf8>().toDartString();
 }
 if (context != null && message.isNotEmpty) {
 message = '$context: $message';
 }
 return KeePassError(-1, message);
 }

 static void checkResult(int code, [String? context]) {
 if (code != 0) {
 throw KeePassError.fromLastError(context);
 }
 }

 factory KeePassError.fromCode(String code, String message) {
 return KeePassError(-1, '[$code] $message');
 }

 @override
 String toString() => 'KeePassError($code): $message';
}
