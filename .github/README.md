# CI dependency checkout

ManyKee's Dart workspace contains the canonical app, whose path dependencies
resolve a sibling `ManyUI` checkout. Every workflow that bootstraps the Dart
workspace therefore checks out ManyKee as `ManyKee/` and the compatible
ManyUI revision beside it as `ManyUI/`.

Configure the repository Actions secret `DEPENDENCY_CHECKOUT_TOKEN` with a
read-only personal access token that can clone the private
`sneurlax/manyui` repository. The workflows fail closed when that secret is
absent; they never fall back to the current repository's job token. ManyUI is
pinned in each workflow to the full commit SHA used by the product release.
