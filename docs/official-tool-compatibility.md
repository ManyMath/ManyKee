# Official Tool Compatibility

Local setup for the ManyKee compatibility harness. KeePassXC is the required automated reference. KeePass 2.x and KPScript are optional evidence only.

Official-tool integration is limited to tests, maintainer scripts, docs, fixture generation, and compatibility evidence. Production runtime code must not shell out to KeePassXC, KeePass, or KPScript.

## Required: KeePassXC 2.7.12

The compatibility workflow requires `keepassxc-cli` 2.7.12. The harness discovers the CLI, verifies the version, and records the exact executable path so evidence can be tied to a concrete reference.

```bash
keepassxc-cli --version
```

If a different version is on `PATH`, point the harness at the correct binary with `MANYKEE_KEEPASSXC_CLI`.

## Optional: KeePass 2.61 and KPScript 2.61

Reported as separate evidence. Not required. KeePassXC compatibility work must not block on a Mono, Wine, or Windows setup.

Do not treat KeePass 2.x results as KeePassXC proof. Optional evidence stays in its own lane.

## Workflow commands

Authoritative workflow:

```bash
scripts/verify_official_compat.sh
```

Melos convenience wrappers:

```bash
melos run verify:compat:official
melos run verify:compat:fixtures
```

Focused Rust harness:

```bash
cargo test --manifest-path rust/Cargo.toml -p keepassxc --test official_tool_harness
```

Prefer the script for maintainer evidence: it runs the required-mode preflight, official compatibility tests, fixture corpus tests, recorder checks, and matrix freshness check in the intended order.

## Bidirectional parity

Required-mode bidirectional parity workflow for the supported KeePassXC CLI fixture set:

```bash
scripts/verify_bidirectional_parity.sh
```

Melos wrapper:

```bash
melos run verify:compat:parity
```

Run the official fixture workflow first, then parity:

```bash
scripts/verify_official_compat.sh
scripts/verify_bidirectional_parity.sh
```

Required parity inputs (the supported KeePassXC fixture IDs):

- `keepassxc-password-basic`
- `keepassxc-keyfile-basic`
- `keepassxc-password-keyfile`
- `keepassxc-richcontent`
- `keepassxc-attachments`
- `keepassxc-history-recycle-deleted`

Two required directions: `official KeePassXC -> ManyKee -> KeePassXC` and `ManyKee -> KeePassXC -> ManyKee`. The first opens official fixtures with ManyKee, writes or classifies the ManyKee output, and uses KeePassXC inspection as supporting proof. The second covers ManyKee-written fixtures, KeePassXC inspection, and ManyKee reopen.

Parity evidence is committed as lane-separated JSON and semantic snapshots:

- `fixtures/compat/evidence/manykee-read-*.json`
- `fixtures/compat/evidence/manykee-write-*.json`
- `fixtures/compat/snapshots/*.semantic.json`

Scope boundaries:

- No byte-identical KDBX requirement; semantic comparison is the proof.
- No manual_pending fixture requirement; GUI-only cipher/KDF and unknown XML stay visible but non-required.
- No Mono/Wine/KeePass/KPScript requirement.
- No parser/writer repair in this workflow; current gaps are recorded as fixture-backed evidence.
- Temporary KDBX files are not committed; only stable evidence, snapshots, docs, scripts, and source.

## Fidelity and merge

KDBX3 save-version, TOTP recognition, and DeletedObject export gaps are closed against the KeePassXC CLI fixture corpus. Deterministic merge-semantics coverage lives at the Rust core layer. Closed gaps are represented by supported ManyKee-write evidence and matching semantic snapshots.

Merge semantics suite:

```bash
cargo test --manifest-path rust/Cargo.toml -p keepassxc --test merge_tests -- --test-threads=1
MANYKEE_REQUIRE_OFFICIAL_TOOLS=1 cargo test --manifest-path rust/Cargo.toml -p keepassxc --test merge_tests -- --test-threads=1
```

Required-mode exercises `test_merge_output_opens_in_keepassxc` against the real `keepassxc-cli` 2.7.12 binary.

Full maintainer gate:

```bash
scripts/verify_official_compat.sh
scripts/verify_bidirectional_parity.sh
cargo test --manifest-path rust/Cargo.toml -p keepassxc --test merge_tests -- --test-threads=1
```

## Cross-surface smoke

Thin cross-surface smoke layer on top of the Rust gate. Every supported library, plugin, and app surface (Dart `package:keepass` FFI, Dart `package:keepass_cli` process, WASM via Rust browser tests and JS jest, and `packages/keepass_flutter/example` Linux-desktop integration) opens a small subset of the committed KeePassXC 2.7.12 fixture corpus end-to-end.

Intent: regression tripwire per surface, not exhaustive parity. A failing smoke test's name identifies the surface and fixture, pointing at the broken binding. Exhaustive coverage stays in the Rust-core harness.

Fixture subset:

- `keepassxc-password-basic.kdbx`: required on every surface (password-only KDBX4, smallest stable baseline).
- `keepassxc-richcontent.kdbx`: best-effort, included where the surface decodes rich entry metadata.
- `keepassxc-attachments.kdbx`: only exercised where the binding exposes attachments.

Per-surface commands (from repo root unless noted):

Dart SDK (`package:keepass`):

```bash
cargo build --manifest-path rust/Cargo.toml -p keepassxc-ffi
cd packages/keepass && dart test test/official_fixture_smoke_test.dart
```

Dart CLI (`package:keepass_cli`):

```bash
cd packages/keepass_cli && dart test test/official_fixture_smoke_test.dart
```

WASM (Rust browser test):

```bash
wasm-pack test --chrome --headless rust/keepassxc-wasm
```

WASM (JS jest):

```bash
wasm-pack build rust/keepassxc-wasm --target web --out-dir ../../packages/keepass_web/web/pkg
cd packages/keepass_web/test_js && npm install && npm test
```

Flutter example (Linux desktop):

```bash
cd packages/keepass_flutter/example && flutter test integration_test -d linux
```

`melos run test:integration` runs the same Flutter command with the standard Melos filters.

Skipped-test policy: each smoke test skips (not fails) when its prerequisite is missing, and the skip message names the missing prerequisite:

- Dart SDK smoke skips when `libkeepassxc_ffi` is not built (rebuild: `cargo build --manifest-path rust/Cargo.toml -p keepassxc-ffi`).
- Dart CLI smoke skips when the FFI library or built CLI snapshot is missing.
- WASM Rust browser test skips when `wasm-pack` or headless Chrome is unavailable.
- WASM JS jest skips when `packages/keepass_web/web/pkg/` has no built WASM module (regenerate: `wasm-pack build rust/keepassxc-wasm --target web --out-dir ../../packages/keepass_web/web/pkg`).
- Flutter example integration skips when `flutter` is absent or no Linux desktop device is configured.

`MANYKEE_REQUIRE_OFFICIAL_TOOLS=1` promotes those skips to failures. Use required mode in maintainer runs, not ordinary developer runs.

### Non-goals (explicit)

The following are out of scope and not exercised by smoke tests, the Rust gate, or any compatibility evidence:

- Browser native messaging (KeePassXC-Browser protocol, extension pairing, handshake).
- Passkey creation and passkey authentication (FIDO2/WebAuthn credentials in KDBX).
- KeeShare synchronization (signed/unsigned containers, shared group sync).
- SSH Agent integration (adding/removing keys into a running agent).
- Secret Service integration (freedesktop Secret Service API, D-Bus bridge).
- Auto-Type execution (global hotkey listener, window-title matching, keystroke synthesis).
- Health and HIBP reports (password health scoring, Have-I-Been-Pwned online and offline lookup).
- Broad import/export as product features (CSV, 1Password, Bitwarden, Proton Pass, HTML, XML are not shipped and not tested as user flows).
- Search-syntax parity with KeePassXC (field-scoped queries, regex and modifier flags, full-text grammar).
- KDBX 3.x read or write support.
- KeePass 1 `.kdb` read or write support.
- Public publishing to pub.dev / npm / Flutter-plugin / extension-store registries. Source, local testing, and compatibility evidence only.

These are load-bearing scope decisions. Do not add smoke coverage, evidence lanes, or matrix rows for them.

## Official fixture corpus

Requires KeePassXC CLI 2.7.12. Deterministic fixtures are generated or checked from `keepassxc-cli` with synthetic credentials. Manual fixtures remain explicit `manual_pending` records until a provenance-clear official source exists.

Run the official fixture recorder directly when updating artifacts:

```bash
cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_official_fixture_evidence -- --write
cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_official_fixture_evidence -- --check
```

Run the starter recorder and corpus tests when validating shared evidence state:

```bash
cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_compat_evidence -- --check
cargo test --manifest-path rust/Cargo.toml -p keepassxc --test official_fixture_corpus
```

Regenerate the matrix:

```bash
scripts/generate_compat_matrix.sh --write
scripts/generate_compat_matrix.sh --check
scripts/verify_official_compat.sh
```

Deterministic KeePassXC fixture IDs:

- `keepassxc-password-basic`
- `keepassxc-keyfile-basic`
- `keepassxc-password-keyfile`
- `keepassxc-richcontent`
- `keepassxc-attachments`
- `keepassxc-history-recycle-deleted`

Manual/pending KeePassXC fixture IDs:

- `keepassxc-gui-argon2id-aes`
- `keepassxc-gui-argon2d-chacha20`
- `keepassxc-gui-argon2id-twofish`
- `keepassxc-unknownxml`

Manifest ownership is split by recorder. `record_compat_evidence` owns `starter-richcontent`. `record_official_fixture_evidence` owns `keepassxc-*`. Each recorder's `--check` validates only its owned section while preserving entries owned by the other.

Fixture credentials are synthetic and reproducible. They may be documented in fixture metadata when needed for clean-checkout regeneration, but they must not appear in process argv, raw command logs, or user-secret locations. Passwords go through stdin; key material is committed only when it is synthetic fixture material.

Attachment proof uses KeePassXC `attachment-import` and `attachment-export` hash equality. XML export must not be used as attachment proof because KeePassXC XML export omits attachments.

`keepassxc-unknownxml` remains `manual_pending` until a provenance-clear official source can create or preserve the unknown XML. KeePassXC XML import skips unknown XML and is not accepted as proof for this fixture.

Optional KeePass 2.61/KPScript evidence remains in the `keepass_optional` lane with `not_observed` status unless a maintainer provides validated optional evidence. Optional KeePass records are never required KeePassXC proof.

## Compatibility matrix

The matrix is generated evidence, not hand-maintained documentation. Sources of truth:

- `fixtures/compat/manifest.json`
- `fixtures/compat/evidence/*.json`
- `fixtures/compat/snapshots/*.semantic.json`

`docs/compatibility-matrix.md` is generated and must not be hand-edited:

```bash
cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_compat_evidence -- --check
scripts/generate_compat_matrix.sh --check
scripts/generate_compat_matrix.sh --write
```

The matrix keeps KeePassXC, optional KeePass, ManyKee read, and ManyKee write as separate lanes. A passing ManyKee read claim is not KeePassXC evidence. Optional KeePass evidence is not KeePassXC evidence. Each support cell is backed by a lane-specific evidence record, explicit `not_observed` status, known gap, non-goal, or unsupported source.

## Environment variables

`MANYKEE_KEEPASSXC_CLI` points the harness at a specific `keepassxc-cli` executable. Use it when the required 2.7.12 binary is not the first matching binary on `PATH`.

```bash
MANYKEE_KEEPASSXC_CLI=/usr/bin/keepassxc-cli scripts/verify_official_compat.sh
```

`MANYKEE_REQUIRE_OFFICIAL_TOOLS=1` switches official-tool checks from skip mode to required mode. Missing tools and version mismatches fail clearly instead of being skipped.

```bash
MANYKEE_REQUIRE_OFFICIAL_TOOLS=1 cargo test --manifest-path rust/Cargo.toml -p keepassxc --test official_tool_harness
```

## Skipped tests and required mode

Ordinary local runs are developer-friendly. When the official tool is absent or not 2.7.12, ordinary tests skip official-tool checks instead of failing unrelated work.

In required mode, missing `keepassxc-cli`, a non-2.7.12 version, or an unusable executable fails clearly. Failures name the expected version, discovered path when available, and sanitized tool status. Raw official-tool output is not dumped: it may contain fixture secrets.

## Credential handling

Synthetic fixture credentials only. They may be documented when reproducibility requires it.

Fixture passwords are passed through stdin whenever the official tool supports it. If a tool requires file-based key material, the harness uses restricted temporary files that live only for the test run. Secrets must never be passed through process arguments.

Output, errors, logs, and generated evidence redact fixture credentials as `[REDACTED]` before anything is printed, asserted, or committed.

User secrets must never be accepted into committed artifacts. Use only synthetic fixture credentials for local compatibility evidence.

## Install guidance

Install KeePassXC 2.7.12 from an official release package or your OS package channel if it provides that exact version. Confirm the CLI version before collecting evidence.

Use `MANYKEE_KEEPASSXC_CLI` when multiple KeePassXC versions are installed or when the desired binary lives outside the default `PATH`.

KeePass 2.61 and KPScript 2.61 may be installed separately for optional investigation. Mono/Wine/`KeePass.exe`/`KPScript.exe` automation is not in scope here.

## Known local limits

KeePass 2.x automation is optional until a Mono, Wine, or Windows runtime path is validated. Windows runtime proof remains manual.

Dart and Flutter analyzer watcher limits are not part of this harness. This document covers the official-tool compatibility workflow only.
