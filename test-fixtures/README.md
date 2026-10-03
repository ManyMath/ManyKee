# ManyKee Product Fixtures

`Passwords.kdbx` is a synthetic, non-sensitive KDBX database used by the
canonical ManyKee application's native unlock/edit/save/reopen test. Its test
credential is `hunter2`; the test always copies it to a temporary directory
before writing.

The fixture's SHA-256 digest is
`37241b7fc55bd578fcebfdabe55a1593743926583f3e6046c71e0bb9a96850cf`.

`test-vault.kdbx` is a small synthetic vault (password `hunter2`, AES-256
with AES-KDF) holding a "Corporate VPN" entry and a "Finance" group with
"Example Login" and "GitHub" entries. No automated test reads it today; it is
kept as a hand-testing vault for the app's search and auto-lock flows, which
it was added alongside. Its SHA-256 digest is
`ff9a4131a900fa0df8c82a18b7a65c37cd38611bc437211dfc92ff0853ce01f2`.
