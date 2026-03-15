# keepass

Dart SDK for KeePass KDBX databases, powered by a Rust core via `dart:ffi`.

`package:keepass` is the low-level, Flutter-free entry point to ManyKee's
KeePass surface. It exposes `Database`, `Group`, `Entry`, and merge primitives
on top of a prebuilt native library (`libkeepassxc_ffi.{so,dylib,dll}`).

## Most users want `keepass_flutter`

This package does NOT ship a prebuilt native library and does NOT build one
for you at `pub get` time. You must build `libkeepassxc_ffi` yourself from
the ManyKee monorepo and place it on the dynamic library search path before
`Database.open` will succeed.

If you are building a Flutter app, depend on
[`keepass_flutter`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_flutter)
instead. It re-exports the same Dart API and uses cargokit to build and
bundle the native library automatically for Android, iOS, Linux, macOS, and
Windows.

Depend on `package:keepass` directly only when:

- You are writing a pure Dart CLI or server-side app (no Flutter toolchain).
- You are building your own higher-level wrapper.
- You want to ship your own prebuilt native binary alongside your app.

## Quickstart

```dart
import 'package:keepass/keepass.dart';

void main() {
  final db = Database.open('vault.kdbx', password: 'demopass');
  try {
    final root = db.rootGroup;
    print('root: ${root.name} (${root.entryCount} entries)');

    for (final entry in root.entries) {
      print('- ${entry.getField('Title')}');
    }

    db.save('vault.kdbx', password: 'demopass');
  } finally {
    db.close();
  }
}
```

See [`example/`](example/) for a runnable version.

## Building the native library

The package loads `libkeepassxc_ffi` (or `libkeepass_flutter_native` when
running inside a Flutter app) at runtime via `DynamicLibrary.open`. For
non-Flutter use, clone the ManyKee monorepo and build the crate:

```bash
git clone https://github.com/ManyMath/ManyKee.git
cd ManyKee
cargo build --manifest-path rust/Cargo.toml -p keepassxc-ffi --release
```

The resulting artifact lives at:

- Linux:   `rust/target/release/libkeepassxc_ffi.so`
- macOS:   `rust/target/release/libkeepassxc_ffi.dylib`
- Windows: `rust/target/release/keepassxc_ffi.dll`

Place it on the dynamic library search path so the Dart process can find it:

- Next to your compiled executable (`Platform.resolvedExecutable`'s directory
  or its `lib/` subdirectory), or
- In the current working directory (or its `lib/` subdirectory), or
- On `LD_LIBRARY_PATH` (Linux), `DYLD_LIBRARY_PATH` (macOS), or `PATH`
  (Windows).

If loading fails the package throws an `ArgumentError` listing every path it
tried.

### Roadmap: Dart Native Assets

When Dart's
[Native Assets feature](https://github.com/orgs/dart-lang/projects/99/views/1)
graduates from experimental, this package intends to adopt
`hook/build.dart` so that `dart pub add keepass` will compile the Rust crate
during `pub get` for pure Dart consumers. Until then, the manual build flow
below is the only option for non-Flutter use.

## Reference apps

The ManyKee monorepo ships several examples:

- [`keepass_cli`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_cli): pure-Dart command-line tool with `info`, `ls`, `show`, `merge`, and edit commands.
- [`keepass_flutter`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_flutter): native Flutter plugin with cargokit-built binaries; see `example/` for a desktop and mobile reference GUI.
- [`keepass_web`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_web): WASM Worker bridge for Flutter Web.
- [`keepass_ui`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_ui): shared platform-agnostic vault widgets.

## API surface

- `Database.open`, `Database.openWithKeyFile`, `Database.openWithYubiKey`
- `Database.save`, `Database.saveWithKeyFile`, `Database.saveBytes`
- `Database.rootGroup`, `Database.merge`, `Database.close`
- `Group`: `name`, `entryAt`, `groupAt`, `entries`, `groups`, counts,
  `createEntry`, `createGroup`, `move`
- `Entry`: `getField`, `setField`, `uuid`
- `MergeResult`: structured merge summary
- `KeePassError`: thrown for native failures

## License

MIT, see [LICENSE](LICENSE).
