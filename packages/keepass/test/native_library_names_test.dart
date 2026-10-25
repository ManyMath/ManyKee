import 'package:test/test.dart';

import 'support/native_library_names.dart';

void main() {
  test('fixture discovery accepts macOS framework copies and Cargo dylibs', () {
    expect(nativeLibraryFileNames('macos'),
        ['libkeepass_flutter_native.dylib', 'libkeepassxc_ffi.dylib']);
  });
  test('fixture discovery preserves Linux and Windows names', () {
    expect(nativeLibraryFileNames('linux'),
        ['libkeepass_flutter_native.so', 'libkeepassxc_ffi.so']);
    expect(nativeLibraryFileNames('windows'),
        ['keepass_flutter_native.dll', 'keepassxc_ffi.dll']);
    expect(nativeLibraryFileNames('unsupported'), isEmpty);
  });
}
