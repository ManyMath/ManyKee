## Unreleased

- Breaking: `KeePassWebApi.saveDatabase` no longer takes `yubiKeySlot`,
  `yubiKeySerial` or `localChallengeHex`. They were ignored; the WASM core
  cannot write a challenge-response factor.
- `WorkerBridge.init()` is idempotent and `dispose()` terminates the worker.
  Worker-level errors and unsendable messages fail pending calls with
  `WORKER_ERROR` instead of leaving them pending.
- `yubikeyChallengeResponse` pads the challenge like the native path, takes an
  optional `slot`, and handles CTAPHID keepalive and error frames.
  `requestYubiKey` returns `null` only when the chooser is dismissed.

## 0.1.0

- First publishable release of the web SDK.
- `KeePassWebApi` exposes the same web-safe API shape as the native KeePass
  API without importing `package:keepass`, backed by a WASM module hosted in a
  Web Worker.
- `WorkerBridge`, `KeePassWebError`, and WebHID YubiKey challenge-response
  helpers exposed for app integration.
- The Dart API avoids importing `package:keepass` so web consumers do not pull
  `dart:ffi` into browser builds.
- `WebFileStorageProvider` (which depended on `package:keepass_ui`) is
  relocated to the reference example so the published package stays free of
  workspace-only deps.
