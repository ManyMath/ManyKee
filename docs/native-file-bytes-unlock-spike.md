# Native File Bytes Unlock Spike

Status: open. The native unlock path still passes the picked file's path to
the worker (`apps/ManyKee/lib/src/unlock/unlock_page.dart`,
`native_vault_state.dart`), and the security-scoped bookmark half of this
plan has landed; the byte-based open steps below have not. Keep this doc
until a decision closes it.

## Question

Can ManyKee open files selected by the native file picker from in-memory bytes,
instead of passing a sandbox-sensitive filesystem path into the native worker?

## Why This Matters

macOS sandboxing makes persisted raw paths unreliable after relaunch unless
they are paired with security-scoped bookmarks. Opening selected files from
bytes would make the initial picker flow less dependent on native worker file
access, matching the existing web flow.

## Current State

- Web uses `FilePicker` bytes and calls `vault.unlock(...)`.
- Native currently calls `vault.unlockFromPath(...)` unless `dbBytes` is
  present.
- Native `FilePicker` calls set `withData: false`, so `dbBytes` is normally
  null.
- The native `KeePassNativeApi.openDatabase(bytes, ...)` path already exists:
  it writes bytes to a temp file that the worker can open.

## Spike Plan

1. Measure native `FilePicker` behavior with `withData: true` on macOS for
   representative `.kdbx` sizes.
2. Validate memory impact for large databases and document a size threshold if
   needed.
3. Add tests for native `dbBytes` unlock using `FakeVaultState.unlock`.
4. Decide whether save should continue using the original selected path, which
   still requires a bookmark for write-back.

## Expected Outcome

Use bytes for the immediate native open after a fresh file selection, while
retaining security-scoped bookmarks for recent files and save/write-back.
