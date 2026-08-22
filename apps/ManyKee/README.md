# ManyKee

The main Flutter app for the ManyKee password manager.

Add user-facing features here. Update package APIs and compatibility tests
when those features require changes below the app layer.

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

The older `apps/native` and `apps/web` hosts remain as references while
their tests move into this app or the packages. Add new features to
`apps/ManyKee`.
