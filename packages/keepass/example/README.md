# keepass example

Minimal walkthrough of `package:keepass`: open a KDBX vault and print the
group / entry tree.

## Run

Build the Rust native library first (see the parent
[README](../README.md#building-the-native-library)), then:

```bash
dart run example/keepass_example.dart path/to/vault.kdbx your-password
```

## Looking for a richer demo?

- [`keepass_cli`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_cli): full pure-Dart CLI (info, ls, show, merge, edit).
- [`keepass_flutter/example`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_flutter/example): reference Flutter GUI for desktop and mobile.
- [`keepass_web/example`](https://github.com/ManyMath/ManyKee/tree/main/packages/keepass_web/example): Flutter Web vault browser backed by a WASM Worker.
