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

## Dependency checkout

ManyKee's Dart workspace contains the canonical app, whose path dependencies
resolve a sibling `ManyUI` checkout. Every workflow that bootstraps the Dart
workspace therefore checks out ManyKee as `ManyKee/` and the compatible
ManyUI revision beside it as `ManyUI/`.

Configure the repository Actions secret `DEPENDENCY_CHECKOUT_TOKEN` with a
read-only personal access token that can clone the private
`sneurlax/manyui` repository. The workflows fail closed when that secret is
absent; they never fall back to the current repository's job token.

ManyUI is pinned in each workflow to the full commit SHA of the ManyUI `main`
revision the app is developed against. When ManyUI moves, update the `ref:`
in every workflow in the same commit so the pins cannot drift apart.
