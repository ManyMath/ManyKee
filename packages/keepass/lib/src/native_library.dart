import 'dart:ffi';
import 'dart:io';

DynamicLibrary _loadLibrary() {
  final libraryBaseNames = <String>[
    'keepass_flutter_native',
    'keepassxc_ffi',
  ];

  final libraryFileNames = switch (Platform.operatingSystem) {
    'macos' ||
    'ios' =>
      libraryBaseNames.map((name) => 'lib$name.dylib').toList(),
    'android' ||
    'linux' =>
      libraryBaseNames.map((name) => 'lib$name.so').toList(),
    'windows' => libraryBaseNames.map((name) => '$name.dll').toList(),
    _ => throw UnsupportedError(
        'Unsupported platform: ${Platform.operatingSystem}',
      ),
  };

  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final cwd = Directory.current.path;

  // Where `cargo build`/`cargo run` drop the native library. The keepassxc-ffi
  // crate lives at <monorepo>/rust, so the workspace target dir is
  // `rust/target/<profile>` from the monorepo root, `../../rust/target/
  // <profile>` from this package dir, or `target/<profile>` when run from the
  // crate itself. `cargo build`/`cargo run` produce debug; `--release` produces
  // release.
  final cargoTargetDirs = <String>[
    for (final profile in const ['debug', 'release']) ...[
      '$cwd/rust/target/$profile',
      '$cwd/../../rust/target/$profile',
      '$cwd/target/$profile',
    ],
  ];

  final attempted = <String>[];
  Object? lastError;
  for (final libraryFileName in libraryFileNames) {
    final candidates = <String>[
      libraryFileName,
      '$executableDir/$libraryFileName',
      '$executableDir/lib/$libraryFileName',
      '$cwd/$libraryFileName',
      '$cwd/lib/$libraryFileName',
      for (final dir in cargoTargetDirs) '$dir/$libraryFileName',
    ];

    for (final candidate in candidates) {
      try {
        return DynamicLibrary.open(candidate);
      } catch (error) {
        attempted.add(candidate);
        lastError = error;
      }
    }
  }

  throw ArgumentError(
    'Failed to load native library. Tried: ${libraryFileNames.join(', ')}\n'
    'Resolved executable: ${Platform.resolvedExecutable}\n'
    'Current directory: ${Directory.current.path}\n'
    'Attempted paths:\n${attempted.map((path) => '- $path').join('\n')}\n'
    'Last error: $lastError',
  );
}

final DynamicLibrary nativeLibrary = _loadLibrary();
