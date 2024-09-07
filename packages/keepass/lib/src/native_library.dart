import 'dart:ffi';
import 'dart:io';

const _libName = 'keepassxc_ffi';

DynamicLibrary _loadLibrary() {
 if (Platform.isMacOS || Platform.isIOS) {
 return DynamicLibrary.open('lib$_libName.dylib');
 }
 if (Platform.isAndroid || Platform.isLinux) {
 return DynamicLibrary.open('lib$_libName.so');
 }
 if (Platform.isWindows) {
 return DynamicLibrary.open('$_libName.dll');
 }
 throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

final DynamicLibrary nativeLibrary = _loadLibrary();
