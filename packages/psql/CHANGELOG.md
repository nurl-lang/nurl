# Changelog

## [0.4.0] — 2026-10-03

Requires NURL 0.69.0 and cli ^0.4 (the `Cli` handle).

Nothing is released by hand any more.

- `PgConn` is a handle instead of a `*PgConn` pointer: every copy is the
  same connection, and the last owner does what `pg_close` did — a
  best-effort Terminate (once the startup message went out), then closes
  the TLS session or the socket. `pg_connect` → `!PgConn PgErr`; a failed
  connect or login releases its connection with the error. `pg_query`
  takes the handle.
- New lent accessors replace reaching into the struct: `pg_conn_lasterr`,
  `pg_conn_tls`, `pg_conn_server_version`, `pg_conn_db_name`,
  `pg_conn_user_name`, `pg_conn_host_name`.
- `pg_close` and `pg_result_free` are optional early releases; every
  redundant release in the library and the CLI is gone.
- Fixed: each server ErrorResponse leaked the previous `lasterr` text.
- Fixed: `psql --version` reported 0.3.1; it now matches the manifest.

## 0.3.2

`pg_result_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.3.1 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
