## 0.1.0

- First publishable release of the web SDK.
- `KeePassWebApi` exposes the same web-safe API shape as the native KeePass
  API without importing `package:keepass`, backed by a WASM module hosted in a
  Web Worker.
- `WorkerBridge`, `WorkerError`, and WebHID YubiKey challenge-response
  helpers exposed for app integration.
- The Dart API avoids importing `package:keepass` so web consumers do not pull
  `dart:ffi` into browser builds.
- `WebFileStorageProvider` (which depended on `package:keepass_ui`) is
  relocated to the reference example so the published package stays free of
  workspace-only deps.
