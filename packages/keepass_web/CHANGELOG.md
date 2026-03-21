## 0.1.0

- First publishable release of the web SDK.
- `KeePassWebApi` implements the platform-agnostic `KeePassApi` from
  `package:keepass`, backed by a WASM module hosted in a Web Worker.
- `WorkerBridge`, `WorkerError`, and WebUSB YubiKey challenge-response
  helpers exposed for app integration.
- Internal `package:keepass/src/...` import replaced with the public
  `package:keepass/keepass.dart` entry point.
- `WebFileStorageProvider` (which depended on `package:keepass_ui`) is
  relocated to the reference example so the published package stays free of
  workspace-only deps.
