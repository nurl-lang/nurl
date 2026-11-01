# Changelog

## [0.6.0] — unreleased

Requires NURL 0.78.0.

### Added

- **Implicit pipelining.** The copies of one `PgConn` — on any number of fibers or threads — now use it at the same time: each request is queued with its own Sync and the answers come back in the order the requests went out, so N callers keep up to N queries in flight on one socket. Measured on one connection (loopback PostgreSQL 16, `SELECT $1::int4 + 1`, `tests/pipeline_bench.nu`, one runtime worker): 1 fiber 33.7k queries/s; 2 fibers 122k; 32 fibers 131k; 128 fibers 150k — where 0.5.1 carried one query at a time (26k/s at best) and DEADLOCKED with two fibers on one worker.
- Whoever queues a request while nobody drives the socket drives it: it writes what is queued (everything queued while it waited leaves in one write), reads, and hands each answer to its request through a one-shot channel until its own is in, then hands the socket on. No thread per connection, no lock held during I/O; a waiting fiber parks and a waiting thread blocks.
- `tests/pipeline_bench.nu`: queries per second on one connection for 1..N fibers (`PSQL_BENCH_WORKERS` runtime workers).
- `pg_connect_url url` — the same connection from a `postgres://[user[:password]@]host[:port][/database][?sslmode=…]` URI (`postgresql://` too), the form `DATABASE_URL` and hosting dashboards hand out. User, password and database are percent-decoded; the port defaults to 5432, the user to `postgres`, the database to the user's name; sslmode is `disable`, `prefer` (the default), `require` or `verify-full`. Another scheme, no host, or any other query parameter is the new `PgBadUrl`: a setting the caller wrote is never ignored.
- `pg_result_col_fmt r col` — the format a column's cells came in (0 text, 1 binary).
- `pg_connect_with dialer host port user password database sslmode` and `pg_connect_url_with dialer url` — the socket dialed through a std/net `NetDialer`: the kernel's (what `pg_connect` uses), or a node of a simulated network (`netsim_dialer`), so the same client runs over it unchanged (agora #249) — TLS too: the SSLRequest and the upgrade run over whatever the dialer connected (agora #250, #289).
- `pg_query_many conn sql sets` — the same statement once per parameter set, every run queued in one hold and so in one write: N runs cost one round trip, not N (what a request that needs N rows by key wants). The statement cache and its stale-statement retry are `pg_query_params'`; each run keeps its own Sync, so a failed run ends only itself and the call fails with the first one that did. Measured on the bench's `/queries?queries=20` (two workers, 64 connections): 315 → 218 µs of server CPU per request (hyper + tokio-postgres `try_join_all`: 215).

### Changed

- **The driver hands over every answer a read brought, then lets go.** Stopping at its own answer made each of the others wait for the socket to change hands — a wake-up, a lock round and a write per request instead of per batch. Measured on `bench/http_server.nu`'s `/db` (two workers, 64 connections, loopback PostgreSQL 16, pinned): 55k → 86k requests/s and 30.5 → 19.8 µs of server CPU per request (hyper + tokio-postgres: 90k, 19.1 µs); `tests/pipeline_bench.nu` with two workers: 39–44k → 69–118k queries/s for 8–128 fibers. On ONE worker it is 93–110k where it was 117–145k for 32–128 fibers: there the server is the bottleneck, and it spends more per query (its user and system time both) when its client goes quiet between batches than when one request at a time trickles in — the client's own CPU per query is unchanged.
- **About seven times less allocation per query.** A result shares its statement's column description (an `Arc`) instead of copying it twice, keeps the CommandComplete tag in its own buffer, and an answer carries an error notice or a statement's parameter types only when it has one; the socket is never handed over with a collector made only to be replaced, and queued requests are copied into the driver's buffer rather than given a fresh one. (Callgrind, the pipeline bench: 24.7k → 9.4k instructions per query.)
- The cell accessors (`pg_row_i`, `pg_row_view`, `pg_row_s`, …) find a cell's offset and length with one bounds check and one span read; each computed the span twice.
- `PgResult.cols` is an `( Arc ( Vec PgCol ) )` and `PgResult.tag` became `tag_off` / `tag_len` (spans of `data`): read them through `pg_result_col`, `pg_result_col_type`, `pg_result_col_fmt`, `pg_result_col_index` and `pg_result_tag`. In the codec, `PgCollect.err` and `PgCollect.param_oids` are options.

### Fixed

- **Fibers sharing a connection no longer deadlock.** 0.5.1 checked the whole connection out of a `Locked` for each round trip; a fiber that parked on the socket while holding it blocked every other fiber's worker in `locked_take` (two fibers on one worker hung forever; with 4 workers, 8 fibers hung). The send side is now held only between I/O.
- An error ends only its own request (one Sync each); a lost stream fails every request on its way with `PgConnFail`, and the next request fails at once.
- The statement cache is consistent under concurrent use: a lookup and the Bind it queues happen under one hold, so no Close another request queues can overtake that Bind on the wire; two requests preparing the same SQL at once keep one and close the other. With the cache off, each execution prepares a statement under its own name and closes it in the same request (an unnamed statement could be replaced by another request's Parse between the two round trips).

## [0.5.1] — 2026-10-27

Requires NURL 0.78.0.

### Changed

- The statement cache takes a statement out, or prepares one under a
  fresh name, inside the `??` arm itself. 0.5.0 needed a helper
  (`__pg_stmt_take`) because an arm ending in `\ ( call )` did not hand
  back an owned value before NURL 0.78.0 (agora #72). No change in
  behaviour.

## [0.5.0] — 2026-10-21

Requires NURL 0.77.0 (`stdlib/std/pool.nu`, and the compiler fix that
drops a library handle a generic function hands back in a result).

### Added

- **The extended query protocol.** `pg_query_params conn sql params`
  binds `$1 … $n` to typed `PgVal` parameters (`PgInt`, `PgFloat`,
  `PgBool`, `PgText`, `PgBytes`, `PgTimestamp`, `PgDate`, `PgNull`) —
  never interpolated into the SQL. The server infers every parameter's
  type (Parse + Describe) and each value goes the way its type takes it:
  binary where exact, its text form otherwise.
- **Binary results** for int2/4/8, oid, float4/8, bool, uuid, date, time,
  timestamp/timestamptz and bytea, and **typed accessors** answering `?T`
  (F for NULL): `pg_row_i`, `pg_row_f`, `pg_row_b`, `pg_row_s`,
  `pg_row_bytes`, `pg_row_ts`, `pg_row_date`, `pg_row_view`,
  `pg_row_is_null`, plus `pg_result_col_type`, `pg_result_col_index`,
  `pg_result_tag`, `pg_result_affected`.
- **A per-connection prepared-statement cache** keyed by SQL text:
  bounded (64, `pg_conn_set_stmt_cache`; 0 = unnamed statements), least
  recently used closed on the server; a statement gone stale (26000 /
  0A000) is prepared again and rerun outside a transaction.
- **`pg_pool_new` / `pg_pool_get`** — a connection pool over
  `stdlib/std/pool.nu`, shared by fibers and threads; a connection that
  lost its stream is dropped, one left in a transaction rolled back
  (`pg_conn_reset`).
- `pg_conn_sqlstate`, `pg_conn_ok`, `pg_conn_txn_status`,
  `pg_conn_stmt_count`; `PgErr` gains `PgInsecureAuth`, `PgPoolTimeout`,
  `PgPoolClosed`.
- `src/pgwire.nu`: the protocol as a message codec with no socket and no
  lock (encoders, framing, a collector folding one request's answer), the
  layer a pipelining connection reuses.
- Tests: `tests/wire_test.nu` (77 codec checks, no server),
  `tests/live_test.nu` (69 checks against a server, gated on
  `PSQL_TEST_PORT`), `tests/live_smoke.sh` (starts a throwaway cluster).

### Changed

- **`sslmode=prefer` no longer hands a password to a server reached by
  falling back from TLS** unless through SCRAM: a cleartext or MD5
  request there is refused with `PgInsecureAuth` (`disable` sends it).
  The CLI reads `$PGSSLMODE`; the README says to use `verify-full`.
- Results are one byte buffer per result plus an (offset, length) span
  per cell, filled with one copy per row, instead of a `String` per
  cell; messages are framed in place instead of copying the rest of the
  receive buffer per message. A 200 000-row query through the CLI
  retires 1.22 G instructions instead of 2.69 G in plaintext and 1.31 G
  instead of 1.64 G over TLS (callgrind).
- A script's result is its last statement's rows (rows of earlier
  statements were mixed in under the last one's columns).
- A connection used by a fiber and then by a thread (a pooled one) works:
  a thread's request puts the socket back into blocking mode.

## [0.4.5] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- The connection is a `TcpConn` (`tcp_connect`, then `tcp_starttls` for the SSLRequest upgrade) in a `Locked`, instead of a raw socket handle, a zeroed `TlsConn` and an `Arc` changed through a raw pointer. The password prompt is `term_read_password`. No function is `unsafe` any more; a 200 000-row result over TLS reads in 543 ms where it took 606 ms.
- 20 fewer functions are `unsafe` than in 0.4.4 (0 left).

## [0.4.4] — 2026-10-12

Requires NURL 0.73.0, in which a standard-library handle holds its
state in a `( Shared T )` (stdlib/core/rcbox.nu): a zero handle is the
cast `# File # s 0`, no longer the literal `@ File { # s 0 }`. The
published 0.4.3 does not compile under it.

### Changed

- The `TcpConn` over the connection's socket is a view (`tcp_conn_view`): NURL 0.73.0's `TcpConn` closes its socket when its last owner goes, and this one belongs to the connection record, whose drop closes it.
- The zero `TlsConn` handle this package keeps until one
  is made is built with the cast. No change in behaviour.

## [0.4.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.4.2 does not compile under it.

### Changed

- `PgConn` keeps its state in an `Arc` (stdlib/std/arc.nu) instead of an
  `rcbox`. The share and drop hooks are ordinary safe functions — the Arc
  does the counting — and so are the constructors that build one from a
  whole value; every copy is still the same state, and its last owner
  releases it.
- One fewer function is `unsafe` than in 0.4.2.
- Its `--version` (or the version it reports) is read from `nurl.toml`
  with `( pkg_version )` instead of being written by hand, so it can no
  longer drift from the manifest.

## [0.4.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.4.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.4.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.4.0 does
not compile under 0.71.0.

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
