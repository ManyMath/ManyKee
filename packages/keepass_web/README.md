# keepass_web

KeePass KDBX SDK for the web. Exposes a `KeePassWebApi` surface that mirrors
the platform-agnostic native API without importing `package:keepass` or
`dart:ffi`, backed by a WASM module hosted in a dedicated Web Worker.

## Why this package

Use `keepass_web` when you are building a Flutter Web (or pure Dart web)
application that needs to open and edit KDBX vaults entirely in the browser.
The WASM core runs off the main thread so unlock and Argon2 work do not
block the UI.

For native (mobile, desktop, server) targets, depend on
[`keepass_flutter`](https://pub.dev/packages/keepass_flutter) (Flutter) or
[`keepass`](https://pub.dev/packages/keepass) (pure Dart) instead.

## Install

```yaml
dependencies:
  keepass_web: ^0.1.0
```

### You must supply the WASM module

This package does NOT ship a prebuilt WASM artifact and does NOT build one
for you at `pub get` time. You must build `keepassxc_wasm` from the ManyKee
monorepo and place it under `web/pkg/` in your app, alongside the worker
bootstrap script shown in this repo's [`web/keepassxc_worker.js`](web/keepassxc_worker.js):

```bash
git clone https://github.com/ManyMath/ManyKee.git
cd ManyKee/rust/keepassxc-wasm
wasm-pack build --release --target web --out-dir ../../packages/keepass_web/web/pkg
```

The output is `keepassxc_wasm.js` plus `keepassxc_wasm_bg.wasm` (and the
matching `.d.ts` files). Copy them into your Flutter app's `web/pkg/`
directory and serve them alongside `web/keepassxc_worker.js`.

### Roadmap: Dart Native Assets

When Dart's
[Native Assets feature](https://github.com/orgs/dart-lang/projects/99/views/1)
gains stable web support, this package intends to adopt `hook/build.dart`
so that `dart pub add keepass_web` will produce the WASM bundle during
`pub get`. Until then, the manual `wasm-pack` flow above is the only option.

## Usage

```dart
import 'package:keepass_web/keepass_web.dart';

Future<void> openVault(List<int> kdbxBytes, String password) async {
  final api = KeePassWebApi();
  await api.init();
  final handle = await api.openDatabase(kdbxBytes, password: password);
  final groups = await api.listGroups(handle);
  for (final group in groups) {
    print(group['name']);
  }
  await api.closeDatabase(handle);
}
```

See [`example/`](example/) for a full Flutter Web vault browser.

## What ships in the SDK

- `KeePassWebApi`: web-safe API that proxies all calls to the WASM worker.
- `WorkerBridge`: low-level RPC over `postMessage` with progress streaming.
- `WorkerError`: typed errors returned by the worker.
- YubiKey helpers (`isWebUsbAvailable`, `requestYubiKey`,
  `yubikeyChallengeResponse`): HMAC-SHA1 challenge-response unlock over
  WebHID (`navigator.hid`, Chromium-based browsers only).

Higher-level state and storage classes (`VaultState`, file pickers, etc.)
live in [`keepass_ui`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_ui)
and in the reference example, not in this SDK.

## Platform support

| Platform | Status                                                   |
| -------- | -------------------------------------------------------- |
| Web      | Supported (Chrome, Firefox, Safari; requires WASM + Worker). |
| Native   | Not supported; use `keepass_flutter` or `keepass`.       |

## License

MIT, see [LICENSE](LICENSE).
