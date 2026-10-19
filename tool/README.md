# Private native package candidates

Canonical native ownership remains under `rust/`. The Flutter wrapper remains
thin for monorepo development. **Publish only the verified staged archive**:
ordinary publication directly from `packages/keepass_flutter` omits required
external sources and is unsupported. This phase creates private candidates only.

```sh
DASH__SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true \
  python3 tool/native_payload.py --config tool/payload.json \
  --mode candidate --output /tmp/manykee-candidate
DASH__SUPPRESS_ANALYTICS=true FLUTTER_SUPPRESS_ANALYTICS=true \
  python3 tool/native_payload.py --config tool/payload.json \
  --mode hosted --output /tmp/manykee-hosted
python3 -m unittest discover -s tool/tests -v
```

Use Python 3.12+, Dart 3.13.2, provisioned Flutter and Rust. The payload gate checks that Cargokit's actual configured `stable` toolchain
and Linux target are already installed, and records `rustup run stable rustc
--version --verbose`. The canonical workspace CI uses 1.94.0 separately. Missing
toolchains/targets fail before Cargokit can install them. No installer runs.
Each output directory must be new. The helper copies the candidate checkout to
an isolated temporary snapshot, preserving Git-ignored files for pub's own
`.pubignore` selection. `stage_native.py` refuses checkouts with Git history
and existing staging output. It copies keepass-rs, keepassxc and keepassxc-ffi
under the staged Flutter crate's `sources/` and rewrites only its dependency
path. Canonical source files remain unchanged.

The canonical Rust lockfile seeds resolution of the staged shim closure. The
resulting Cargo.lock ships in the archive with a dependency/license inventory
(`NATIVE_DEPENDENCIES.json`). No external local path remains.

Each source file, lockfile, inventory and transformed manifest has a SHA256 entry in
`rust/SOURCE_PROVENANCE.json`; archive inspection verifies every entry. Repeated
staging of identical source bytes and revision produces identical provenance.
A generated `src/staged_source_identity.rs` binds Cargokit's cache hash to all
copied source bytes; source-only dependency edits cannot reuse stale binaries.
Pub's compressed archive bytes may differ due to metadata timestamps; each
candidate archive has its own recorded SHA256.

The MIT license on keepass-rs preserves Stefan Seemayer's upstream notice.
The ManyMath-authored wrappers use the existing ManyMath package MIT notice.
The exact upstream keepass-rs base revision is not established; the canonical
ManyKee revision plus source hashes identify local modifications precisely.
Do not claim a pristine upstream snapshot or registry crate replacement.

The gate runs separate `pub publish --dry-run` and `--to-archive` commands.
The pinned hidden archive flag writes locally, with no fallback to publication.
It verifies Cargo path closure, licenses, source hashes and candidate dependency
constraints, then builds a fresh Flutter Linux consumer outside the repository.
A separate Dart consumer verifies Linux `/proc/self/maps` contains only its
expected native library copy, then decrypts the upstream
Argon2id test database, saves with a new password and reopens it. The public
fixture password is `demopass`; no real vaults are used.

`candidate` uses coordinated extracted packages after checking original ranges
with pub_semver. `hosted` uses already hosted keepass ^0.1.0 without overrides.
The original archives are retained untouched; extracted local-path pubspecs
have workspace resolution removed to model hosted package resolution.

Candidates: keepass 0.1.1, then keepass_flutter 0.1.1 in the owner's later public
phase. Existing hosted keepass 0.1.0 is tested separately for compatibility.
No package has been published by these commands. Other platform native builds
and physical YubiKey behavior require their own runner/hardware evidence.

## Private CI continuity

Gitea selects `.gitea/workflows` before `.github/workflows`; all four existing
validation tiers are therefore represented in the private directory, alongside
the exact-payload gate. No public workflow was changed or executed. Host jobs
use provisioned tools and isolated Cargo caches, with no toolchain installers
or global cache cleanup. Native UI, product web and browser E2E tiers retain
main/manual triggers; their Xvfb, wasm-pack, browser and WASM target requirements
remain explicit. A configured workflow is not a passing validation result.
