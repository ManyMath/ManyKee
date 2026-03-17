# keepass_flutter

Flutter plugin for KeePass KDBX databases. Bundles a Rust core via
[cargokit](https://github.com/irondash/cargokit) and re-exports the full
Dart API from [`package:keepass`](https://pub.dev/packages/keepass).

## Why this package

Depend on `keepass_flutter` when you are building a Flutter app for Android,
iOS, Linux, macOS, or Windows. It:

- Builds and bundles the native Rust library (`libkeepass_flutter_native`)
  automatically as part of your Flutter build, with no manual `cargo build`
  step.
- Re-exports the full `package:keepass` surface so a single import gives you
  `Database`, `Group`, `Entry`, `MergeResult`, and `KeePassError`.

For non-Flutter Dart code (CLIs, servers), depend on `package:keepass`
directly and supply the native library yourself.

## Install

```yaml
dependencies:
  keepass_flutter: ^0.1.0
```

Then `flutter pub get` (cargokit will compile the Rust crate the first time
you build for a given target).

## Usage

```dart
import 'package:keepass_flutter/keepass_flutter.dart';

void main() {
  final db = Database.open('vault.kdbx', password: 'demopass');
  try {
    final root = db.rootGroup;
    for (final entry in root.entries) {
      print(entry.getField('Title'));
    }
    db.save('vault.kdbx', password: 'demopass');
  } finally {
    db.close();
  }
}
```

See [`example/`](example/) for a full reference GUI: file picker unlock,
group / entry CRUD, idle auto-lock, settings, and YubiKey challenge-response
support.

## What ships in the plugin

The plugin is intentionally thin. It exposes:

- All symbols from `package:keepass` (re-exported).
- A Flutter plugin manifest that wires cargokit into your native build.

Higher-level state classes (`VaultState`, storage providers, etc.) live in
the [`keepass_ui`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_ui)
package and in the reference example, not in this plugin.

## Platform support

| Platform | Status                                  |
| -------- | --------------------------------------- |
| Android  | Supported via cargokit (Android NDK).   |
| iOS      | Supported via cargokit.                 |
| Linux    | Supported via cargokit.                 |
| macOS    | Supported via cargokit.                 |
| Windows  | Supported via cargokit.                 |
| Web      | Not supported; use `keepass_web`.       |

## License

MIT, see [LICENSE](LICENSE).
