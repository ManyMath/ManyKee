/// Names probed by the production loader, in the same preference order.
List<String> nativeLibraryFileNames(String operatingSystem) {
  final bases = ['keepass_flutter_native', 'keepassxc_ffi'];
  return switch (operatingSystem) {
    'macos' || 'ios' => [for (final name in bases) 'lib$name.dylib'],
    'linux' || 'android' => [for (final name in bases) 'lib$name.so'],
    'windows' => [for (final name in bases) '$name.dll'],
    _ => const [],
  };
}
