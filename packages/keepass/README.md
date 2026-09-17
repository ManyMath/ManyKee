# keepass

Dart SDK for KeePass KDBX databases, powered by a Rust core via `dart:ffi`.

`package:keepass` is the low-level, Flutter-free entry point to ManyKee's
KeePass API. It exposes `Database`, `Group`, `Entry`, and merge primitives
on top of a prebuilt native library (`libkeepassxc_ffi.{so,dylib,dll}`).

## Most users want `keepass_flutter`

This package neither includes a prebuilt native library nor builds one
during `pub get`. You must build `libkeepassxc_ffi` yourself from
the ManyKee monorepo and place it where the package looks for it (see
[Building the native library](#building-the-native-library)) before
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

The package does not consult the system library search path in release
builds. It tries these locations in order, first for
`libkeepass_flutter_native` and then for `libkeepassxc_ffi` (with the
platform's `.so`, `.dylib` or `.dll` naming):

1. `<exe dir>/<library>`, where `<exe dir>` is the directory of
   `Platform.resolvedExecutable`.
2. `<exe dir>/lib/<library>`.

Debug/JIT runs only (`dart run`, `dart test`, `flutter run --debug`), never
release/AOT builds (`dart compile exe`, `flutter build`):

3. The bare file name, resolved by the platform loader's own rules. This is
   the only step where `LD_LIBRARY_PATH` (Linux), `DYLD_LIBRARY_PATH` (macOS)
   or `PATH` (Windows) apply.
4. `<cwd>/<library>`, then `<cwd>/lib/<library>`.
5. Cargo output directories: `<cwd>/rust/target/<profile>`,
   `<cwd>/../../rust/target/<profile>` and `<cwd>/target/<profile>`, for
   `debug` and then `release`. A local `cargo build` is therefore found when
   running from the monorepo root, from a `packages/<name>` directory, or
   from `rust/`.

On macOS and iOS the package finally falls back to symbols already linked
into the running process (`DynamicLibrary.process()`), which is how
`keepass_flutter` ships the library there.

A release build of a pure Dart app must therefore ship the library next to
its executable or in that directory's `lib/` subdirectory. If loading fails
the package throws an `ArgumentError` listing every path it tried.

### Roadmap: Dart Native Assets

When Dart's
[Native Assets feature](https://github.com/orgs/dart-lang/projects/99/views/1)
graduates from experimental, this package intends to adopt
`hook/build.dart` so that `dart pub add keepass` will compile the Rust crate
during `pub get` for pure Dart consumers. Until then, the manual build flow
above is the only option for non-Flutter use.

## Reference apps

The ManyKee monorepo ships several examples:

- [`keepass_cli`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_cli): pure-Dart command-line tool with `info`, `ls`, `show`, `merge`, and edit commands.
- [`keepass_flutter`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_flutter): native Flutter plugin with cargokit-built binaries; see `example/` for a desktop and mobile reference GUI.
- [`keepass_web`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_web): WASM Worker bridge for Flutter Web.
- [`keepass_ui`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_ui): shared platform-agnostic vault widgets.

## API

Synchronous, handle-owning classes:

- `Database`
  - Create/open: `Database.create`, `Database.open`,
    `Database.openWithKeyFile`, `Database.openWithYubiKey`,
    `Database.openWithKeyFileAndYubiKey`, `Database.openWithLocalChallenge`,
    `Database.openWithKeyFileAndLocalChallenge`
  - Save: `save`, `saveWithKeyFile`, `saveWithYubiKey`,
    `saveWithKeyFileAndYubiKey`, `saveWithLocalChallenge`,
    `saveWithKeyFileAndLocalChallenge`, and `saveBytes` (returns the
    encrypted bytes for any of those key combinations)
  - `rootGroup`, `merge`, `close`, `Database.listYubiKeys`
- `Group`: `uuid`, `name` (get/set), `entryCount`, `groupCount`, `entryAt`,
  `groupAt`, `entries`, `groups`, `createEntry`, `createGroup`, `move`,
  `delete`
- `Entry`: `uuid`, `getField`, `setField`, `title`/`userName`/`password`/
  `url`/`notes`, `readInfo`, `readFields`, `getTotpCode`, `move`, `delete`
- `MergeResult`: structured merge summary
- `KeePassError`: thrown for native failures; `code` is the native status
  (e.g. `KeePassError.notFound`, `KeePassError.yubiKeyError`) or
  `KeePassError.unknownCode` when the failing call returns no status

Asynchronous, integer-handle API for UI code:

- `KeePassApi`: the platform-agnostic interface (`keepass_web`'s
  `KeePassWebApi` has the same shape)
- `KeePassNativeApi`: the `dart:ffi` implementation. Every native call runs
  on a dedicated worker isolate, so KDF work never blocks the caller. Beyond
  `KeePassApi` it adds path-based openers (`openFromPath`,
  `openFromPathWithKeyFile`, `openFromPathWithYubiKey`,
  `openFromPathWithKeyFileAndYubiKey`, `openFromPathWithLocalChallenge`,
  `openFromPathWithKeyFileAndLocalChallenge`) and `listYubiKeys`. Its
  `openDatabaseWithChallengeResponse` throws `UnsupportedError`; use the
  YubiKey or local-challenge openers instead. After `dispose()` every call
  throws `StateError`.

## License

MIT, see [LICENSE](LICENSE).
