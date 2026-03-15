## 0.1.0

- First publishable release of the Dart SDK for KeePass KDBX databases.
- Open password-protected and key-file databases; YubiKey challenge-response
  unlock via the native Rust backend.
- Read groups and entries by UUID through `Database.rootGroup`, `Group`, and
  `Entry`.
- Write APIs for fields and metadata; save to file (`save`,
  `saveWithKeyFile`) and to bytes (`saveBytes`).
- Database merge with a structured `MergeResult`.
- `NativeFinalizer` integration so handles are freed automatically alongside
  explicit `close()`.
- Generated FFI bindings (`lib/src/bindings.g.dart`) regenerated via
  `dart run ffigen`.

## 0.0.1-dev.1

- Initial development snapshot of the package layout (legacy entry).
- See https://github.com/ManyMath/keepass-dart and https://github.com/ManyMath/keepass-ffi for provenance on this initial version; see the https://github.com/ManyMath/ManyKee monorepo's /packages directory for the new packages post-0.0.1-dev.1.
