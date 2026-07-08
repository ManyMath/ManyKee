# ManyKee

Canonical Flutter application for the ManyKee password-manager surface.

This is the product app. New user-facing work should land here unless a
package-level API or compatibility harness needs to change first.

## Run and Verify

From this directory:

```bash
flutter analyze
flutter test -j 1
flutter build macos --debug
```

From the repository root, use the wrapper for web builds so the KeePassXC WASM
worker assets are built and copied into the Flutter output:

```bash
scripts/build_manykee_web.sh
```

## Legacy App Hosts

The older `apps/native` and `apps/web` hosts are legacy transitional/reference
surfaces. They are not the product entry points and should not receive new
features. Keep them only while they are useful for comparison or while their
remaining tests are being ported into this app or package-level coverage.
