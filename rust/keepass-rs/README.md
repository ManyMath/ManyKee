# keepass-rs (ManyKee fork)

Rust KeePass database file parser for KDB, KDBX3 and KDBX4, with support for
writing KDBX4 and KDBX3.

This is ManyKee's vendored fork of
[sseemayer/keepass-rs](https://github.com/sseemayer/keepass-rs). It lives in
the ManyKee Cargo workspace (`rust/`) and is not published to crates.io; the
`keepassxc`, `keepassxc-ffi` and `keepassxc-wasm` crates use it through a path
dependency. Changes made here are not necessarily present upstream, and
upstream releases are not picked up automatically.

## Usage

Depend on it by path from another crate in the workspace, enabling the
features you need:

```ignore
[dependencies]
keepass = { path = "../keepass-rs", features = ["save_kdbx4"] }
```

Commonly used features:

- `save_kdbx4` / `save_kdbx3`: write databases in that format
- `totp`: TOTP code generation for entries
- `challenge_response`: YubiKey HMAC-SHA1 challenge-response keys
- `serialization`: `serde` serialization of the database model
- `utilities`: the command line tools described below

Examples are available in the [`examples`](./examples) directory.

### Use developer tools

This crate contains several command line tools that can be enabled with the `utilities` feature flag.
See the `[[bin]]` sections in [Cargo.toml](Cargo.toml) for a complete list.

An example command line for running the `kp-dump-xml` command, from the
`rust/` workspace directory:

```bash
cargo run --release -p keepass --features "utilities" --bin kp-dump-xml -- path/to/database.kdbx out.xml
```

### Testing

From the `rust/` workspace directory:

```bash
cargo test -p keepass --all-features
```

`tests/keepassxc_interop_tests.rs` checks that databases written by this crate
are readable by `keepassxc-cli`. Those tests pass without doing anything when
`keepassxc-cli` is not on `PATH`.

### Performance Notes

AES key derivation is much faster with CPU-specific optimizations. The
recommended settings are in [`.cargo/config.toml`](.cargo/config.toml). Cargo
only reads that file when it is invoked from inside `keepass-rs/`, so builds
started from the workspace root need equivalent flags of their own.

## License

MIT, as upstream. See [LICENSE](./LICENSE).
