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
fixture password is `demopass`; no real vaults are used. On Windows,
`GetModuleFileNameW` must name the copied `keepass_flutter_native.dll`, and the
smoke also adds a generated `example.invalid` entry, saves it under a random
password, verifies its fields after reopening and rejects a wrong password.
It uses only API present since keepass 0.1.0, so hosted mode runs it too.
`--to-archive` still reads the hosted version listing during validation.

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

The macOS and Android builds select vendored `rusb`/libusb because the existing
`nusb` adapter does not compile there. Android token operations explicitly fail
until a permission/descriptor bridge exists; iOS excludes the USB dependency.
Other targets retain `nusb`.
The staged native source includes exact wrapper MIT notices, libusb LGPL text
and authors, and locked source archive checksums under
`rust/sources/keepass-rs/third_party/usb/`; the payload gate verifies those hashes.
See the canonical `rust/keepass-rs/third_party/usb/README.md` for static binary
redistribution limits. Passing build/runtime checks is not release clearance.

On iOS, the upstream USB dependency has no supported backend and is excluded from the build. USB token enumeration and challenge operations return the target-specific Rust `UnsupportedUsb` error; local HMAC and core database APIs remain available. This does not add an iOS USB bridge or change C ABI symbols. The iOS-only error variant replaces the unavailable dependency error type only on that previously unbuildable target.

Android APK consumers use the checked-in target map and the installed stable
Rust toolchain; its actual compiler identity is recorded. Set ANDROID_SDK_ROOT
to an SDK with platform36, build-tools36.0.0 and NDK28.2.13676358 already installed
(Glow also needs CMake3.22.1). Run the usual gate with --target apk. The gate
fails before building when tools/targets are absent, disables SDK/JDK downloads
in the fresh consumer, and checks Gradle's actual selected NDK. Child builds
receive the selected Rust toolchain without changing user settings. Gradle and
Android homes default to task-local output directories; explicitly supplied
task-owned homes may be reused. Evidence binds the APK and every expected
native ABI to SHA256. This is build/packaging validation, not device behavior.

The private `android-payload.yml` lane runs on the dedicated maintenance branch or manual dispatch. It uses isolated temporary dependency/build homes and retains archive evidence and the APK, then removes its own intermediate build/cache directories. Linux CI remains the required default lane; Android is an additional build qualification, not a device test.
