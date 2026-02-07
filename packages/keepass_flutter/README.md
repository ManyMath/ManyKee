# keepass_flutter

Flutter plugin and native integration layer for ManyKee's Rust-backed KeePass support.

## Purpose

Depend on `keepass_flutter` when you are building a Flutter app for supported native platforms and want:

- cargokit to build and link the Rust native library automatically
- the Dart KeePass API re-exported from `package:keepass`
- reusable native integration primitives such as `NativeVaultState` and `LocalFileStorageProvider`

Depend on `keepass` directly only for non-Flutter or lower-level Dart use cases.

## Surface

- `package:keepass_flutter/keepass_flutter.dart`
  - re-exports the core Dart KeePass API from `package:keepass`
  - exports the native Flutter-facing state and storage helpers owned by this package

`keepass_ui` remains the shared widget/state package for cross-platform UI pieces. `keepass_flutter` sits between that UI layer and the low-level `keepass` API for native Flutter apps.
