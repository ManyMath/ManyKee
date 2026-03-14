# manual fixtures: keepassxc 2.7.12

password: `manykee-fixture-password`

after dropping a .kdbx here, run:
```
cargo run --manifest-path rust/Cargo.toml -p keepassxc --bin record_official_fixture_evidence -- --write
```

## TODO

- [ ] `keepassxc-gui-argon2id-aes.kdbx`: GUI, new db, AES-256 + Argon2id (CLI doesn't reliably pick this combo)
- [ ] `keepassxc-gui-argon2d-chacha20.kdbx`: GUI, new db, ChaCha20 + Argon2d
- [ ] `keepassxc-gui-argon2id-twofish.kdbx`: GUI, new db, Twofish + Argon2id
- [ ] `keepassxc-unknownxml.kdbx`: needs a real GUI/plugin-generated source with unknown XML intact; XML import strips it so that doesn't count
