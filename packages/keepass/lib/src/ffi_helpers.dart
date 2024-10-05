import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'bindings.g.dart';
import 'error.dart';
import 'native_library.dart';

final KeePassXcFfiBindings bindings = KeePassXcFfiBindings(nativeLibrary);

Pointer<Char> toNativeString(String s) => s.toNativeUtf8().cast<Char>();

String? readAndFreeString(Pointer<Char> ptr) {
 if (ptr == nullptr) return null;
 try {
 return ptr.cast<Utf8>().toDartString();
 } finally {
 bindings.kpxc_string_free(ptr);
 }
}

String readAndFreeStringOrThrow(Pointer<Char> ptr, String context) {
 final result = readAndFreeString(ptr);
 if (result == null) {
 throw KeePassError.fromLastError(context);
 }
 return result;
}
