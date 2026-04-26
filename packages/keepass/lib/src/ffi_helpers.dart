import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'bindings.g.dart';
import 'error.dart';
import 'native_library.dart';

final KeePassXcFfiBindings bindings = KeePassXcFfiBindings(nativeLibrary);

Pointer<Char> toNativeString(String s) => s.toNativeUtf8().cast<Char>();

/// Zeroes the native buffer's contents before freeing it, so secrets
/// (passwords, key material) copied into `malloc`'d memory by
/// [toNativeString] don't linger in freed heap pages (and thus in core
/// dumps/swap) after `malloc.free` alone would leave them.
void freeNativeString(Pointer<Char> ptr) {
 if (ptr == nullptr) return;
 final length = ptr.cast<Utf8>().length;
 ptr.cast<Uint8>().asTypedList(length).fillRange(0, length, 0);
 malloc.free(ptr);
}

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
