## 0.1.1

- Verify source-closed native publication payloads and fresh consumers.
- Bundle the complete Rust dependency source closure in Flutter candidates.
- Build the macOS challenge-response backend with vendored libusb and required
  Apple frameworks; include dependency notices and redistribution provenance.

## 0.1.0

- First publishable release of the Flutter plugin.
- Re-exports the full `package:keepass` Dart API (Database, Group, Entry,
  merge, error types).
- cargokit integration builds and bundles `libkeepass_flutter_native` for
  Android, iOS, Linux, macOS, and Windows so apps load the native code with
  no manual build step.
- State and storage classes that previously lived in `lib/src/state/`
  (NativeVaultState, LocalFileStorageProvider) are relocated to the reference
  example. The plugin itself is now a thin cargokit + re-export layer.

## 0.0.1-dev.1

- Initial development snapshot of the package layout (legacy entry).
- See https://github.com/ManyMath/keepass-dart and https://github.com/ManyMath/keepass-ffi for provenance on this initial version; see the https://github.com/ManyMath/ManyKee monorepo's /packages directory for the new packages post-0.0.1-dev.1.
