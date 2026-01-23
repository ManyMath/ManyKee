# KeePass CLI

A command-line tool for exercising the ManyKee Rust-backed KeePass surface from a terminal.

## Installation

Ensure the Dart SDK is installed and the native Rust library for `package:keepass` has been built for your platform.

## Usage

```bash
dart run bin/keepass_cli.dart <command> [arguments]
```

### Authentication

Most database commands accept:

- `-p`, `--password`: database password
- `-k`, `--keyfile`: key file path
- `--yubikey-slot`: YubiKey challenge-response slot (`1` or `2`)
- `--yubikey-serial`: optional YubiKey serial number

You can provide the password via:

- Flag: `--password yourpassword`
- Environment variable: `KEEPASS_PASSWORD`
- Interactive prompt when stdin is a TTY

`merge` uses `--password1` / `--password2` or the `KEEPASS_PASSWORD1` / `KEEPASS_PASSWORD2` environment variables.

### Commands

#### Discovery

- `info <db>`: display root metadata and counts
- `ls <db> [--group <uuid-or/path>]`: list groups and entries under a group
- `show <db> <entry-uuid-or/path>`: display entry fields
  - `--field <name>` prints only one field value
  - `--totp` includes the live TOTP payload when present
  - `--reveal` shows the password instead of masking it

#### Manipulation

- `add group <db> <name> [--parent <uuid>]`
- `add entry <db> [--parent <uuid>] [--title ...] [--user ...] [--pass ...]`
- `edit <db> <entry-uuid-or/path> [--title ...] [--user ...] [--pass ...] [--url ...] [--notes ...]`
- `edit <db> <group-uuid-or/path> --group --name <new-name>`
- `rm <db> <uuid>`
- `move <db> <uuid> <target-parent-uuid>`
- `merge --db1 <path> --db2 <path> --out <path>`

#### YubiKey

- `yubikey list`
- `yubikey unlock <db> --yubikey-slot <slot>`

### JSON Output

Most commands support `--json` for machine-readable output.

```bash
dart run bin/keepass_cli.dart ls my.kdbx --json
```

## Examples

List the root group:

```bash
dart run bin/keepass_cli.dart ls test.kdbx --password password
```

List a nested group by path:

```bash
dart run bin/keepass_cli.dart ls test.kdbx --password password --group Root/Internet
```

Show one entry and include its TOTP code:

```bash
dart run bin/keepass_cli.dart show test.kdbx "Root/Internet/GitHub" --password password --totp
```

Print only the password field:

```bash
dart run bin/keepass_cli.dart show test.kdbx 01ef4226-f631-4c26-9eea-123a1558e173 --password password --field Password --reveal
```

Create, inspect, and remove an entry:

```bash
dart run bin/keepass_cli.dart add entry test.kdbx --password password --title "My Site" --user "user" --pass "secret"
dart run bin/keepass_cli.dart ls test.kdbx --password password
dart run bin/keepass_cli.dart rm test.kdbx <entry-uuid> --password password
```

Rename a group:

```bash
dart run bin/keepass_cli.dart edit test.kdbx Root/Internet --group --name Personal --password password
```

Merge two databases:

```bash
dart run bin/keepass_cli.dart merge --db1 a.kdbx --db2 b.kdbx --out merged.kdbx --password1 password --password2 password
```
