# CI workflows

The workflows run on the Gitea instance at git.manymath.com (the artifact
upload step uses the Gitea-compatible `gitea-upload-artifact` action), with
GitHub serving as a mirror only.

| Workflow | Covers |
| --- | --- |
| `ci-core.yml` | Rust workspace tests, wasm target check, compat matrix freshness, pure-Dart package tests |
| `ci-product.yml` | Canonical app tests, shared UI tests, ManyKee.com distribution build and verification |
| `ci-native.yml` | Linux desktop integration tests for the legacy native host |
| `ci-web.yml` | Chrome extension build and Puppeteer end-to-end tests |

## ManyUI dependency

The canonical app depends on ManyUI through git dependencies on its public
mirror (https://github.com/ManyMath/ManyUI.git), pinned to a full commit SHA in
the root `pubspec.yaml` and `apps/ManyKee/pubspec.yaml`. `flutter pub get`
fetches it, so the workflows need no extra checkout or token. When ManyUI
moves, update every `ref:` in the same commit so the pins cannot drift apart.
