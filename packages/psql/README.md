# psql — a pure-NURL PostgreSQL client

A PostgreSQL client written entirely in NURL: the **version-3 wire
protocol**, the **authentication** (trust / cleartext / MD5 /
SCRAM-SHA-256) and the **TLS transport** are all implemented from scratch,
with **no libpq and no OpenSSL**. A secure, authenticated connection works
on a machine that has nothing installed — the produced binary links
`libc` only, on Linux, macOS, the BSDs and Windows.

It uses the stdlib's pure-NURL TLS 1.3 / 1.2 client (`std/tls.nu`)
and the stdlib crypto, so the TLS handshake — X25519 **and** NIST P-256
key exchange, ChaCha20-Poly1305 / AES-GCM, the certificate verification —
needs nothing from the host either.

## What's implemented

* **Connection** — TCP, with PostgreSQL's `SSLRequest` negotiation to
  upgrade the same socket to TLS before the startup message.
* **TLS** — opt-in per `sslmode`, over the pure-NURL TLS client. The key
  exchange offers both X25519 and **secp256r1 (P-256)**, so it interoperates
  with the common PostgreSQL/OpenSSL default (`ssl_ecdh_curve = prime256v1`).
* **Authentication**
  * **SCRAM-SHA-256** (RFC 7677) — the modern default, channel-binding-less
    (`SCRAM-SHA-256`, matching libpq's default), built on a pure-NURL
    PBKDF2-HMAC-SHA-256;
  * **MD5** (`md5(md5(password‖user)‖salt)`);
  * **cleartext** and **trust**.
* **Queries**, both protocols:
  * the **extended protocol** for parameterised queries — Parse /
    Describe / Bind / Execute / Sync, every `$n` bound to a typed `PgVal`
    (never interpolated into the SQL), the parameter types inferred by the
    server and each value sent the way its type takes it best: binary for
    integers, floats, bool, bytea, uuid, timestamps and dates, the text
    form otherwise (which the server parses as the inferred type);
  * **binary results** for the fixed-width types (int2/4/8, oid, float4/8,
    bool, uuid, date, time, timestamp/timestamptz, bytea), text for the
    rest, read through **typed accessors** (`pg_row_i`, `pg_row_f`, …)
    that answer `?T` — `F` for NULL;
  * a per-connection **prepared-statement cache** keyed by SQL text:
    the first run of a statement prepares it (one extra round trip), every
    later run is one round trip; bounded (64 by default), the least
    recently used closed on the server when it is full; a statement the
    server no longer has as it was described (`DEALLOCATE ALL`, a table
    altered under it) is prepared again transparently, outside a
    transaction;
  * the **simple protocol** for scripts — any number of statements in one
    `pg_query`, text results, the last statement's rows kept.
  Backend `ErrorResponse`s are surfaced with their SQLSTATE, message,
  detail and hint; the transaction status is tracked.
* **Implicit pipelining** — the copies of one `PgConn` on any number of
  fibers or threads use it at the same time: every request is queued with
  its own Sync and each answer comes back to the request that asked, so N
  callers keep up to N queries in flight on one socket (one connection,
  loopback, one runtime worker: 33.7k queries/s for one fiber, 150k for
  128). An error ends only its own request; a lost stream fails every
  request on its way. The transaction status is the session's: BEGIN …
  COMMIT through copies used at the same time interleaves with their other
  requests — take a pooled connection (below) for a transaction.
* **A connection pool** — `pg_pool_new` over the standard library's
  `Pool` (`stdlib/std/pool.nu`): connections made on demand up to a
  bound, a checkout that waits (bounded) when all are lent — parking the
  fiber on a fiber, blocking the thread on a thread — and gives the
  connection back when its guard goes. A connection that lost its stream
  is dropped, one left inside a transaction is rolled back first.
* **A psql-style front end** — aligned result tables (numeric columns
  right-justified, NULLs blank, an `(N rows)` footer), backslash
  meta-commands, a multi-line REPL that accumulates a statement until its
  `;` terminator, TTY-only prompts and banner, and one-shot `-c`.

## sslmode

| mode          | code | behaviour                                            |
|---------------|------|------------------------------------------------------|
| `disable`     | 0    | plaintext only                                        |
| `prefer`      | 1    | TLS if the server offers it, no certificate check (the CLI's default, as libpq's) |
| `require`     | 2    | TLS mandatory, no certificate check                   |
| `verify-full` | 3    | TLS mandatory + chain & hostname verified against the system trust store |

`prefer` stays the command's default for psql compatibility (`$PGSSLMODE`
overrides it, as for libpq), but it cannot stop a downgrade: anyone in the
path can answer the SSLRequest with "no". So under `prefer` a server that
declined TLS gets the password only through SCRAM-SHA-256, which never
reveals it; one that asks for it in the clear or as MD5 (a hash anyone in
the path could have asked for, and crack offline) is refused with
`PgInsecureAuth` — `disable` is the explicit way to send it anyway. The
library takes `sslmode` from its caller with no default: **use
`verify-full` (3) for any server reached over a network.** `require`
encrypts but does not authenticate the server, so it stops a passive
listener and not an active one. A server with a certificate the system
trust store does not know (self-signed) cannot be verified yet — there is
no `sslrootcert`.

## Use as a command

```
nurlpkg install psql

psql -h localhost -p 5432 -U me -d mydb -c "select 1"
psql --sslmode require -U me -d mydb -c "select * from t"
psql "postgres://me:secret@db.example.com:5432/mydb?sslmode=verify-full" -c "select now()"
```

Run `psql --help` for a usage summary (flags are parsed by the cli package). The password is taken from
`$PGPASSWORD` or the URL; if the server asks for one and neither is set, you
are prompted for it on the terminal (with echo off, like the real `psql`).
`-h/-p/-U/-d` fall back to `$PGHOST/$PGPORT/$PGUSER/$PGDATABASE`. With no
`-c`, it runs an interactive
REPL: SQL is read across lines until a `;`, prompts (`nurl=>` / `nurl->`)
and the banner appear only on a terminal, so piping a script through it
produces clean, prompt-free output.

Backslash meta-commands (when no statement is pending):

| command       | action                          |
|---------------|---------------------------------|
| `\dt`         | list tables                     |
| `\d TABLE`    | describe a table's columns      |
| `\dn`         | list schemas                    |
| `\l`          | list databases                  |
| `\du`         | list roles                      |
| `\conninfo`   | show the connection (and whether it is TLS-encrypted) |
| `\?`          | meta-command help               |
| `\q`          | quit                            |

## Use as a library

```
nurlpkg add psql
```

```
$ `deps/psql/src/pg.nu`

@ main → i {
    : PgConn c ?? ( pg_connect `db.example.com` 5432 `me` `secret` `mydb` 3 ) {
        T x → x
        F e → { ( nurl_eprint `connect failed\n` ) ^ 1 }
    }
    : ( Vec PgVal ) ps ( vec_new [PgVal] )
    ( vec_push [PgVal] ps @ PgVal { PgInt 42 } )
    ( vec_push [PgVal] ps @ PgVal { PgText ( string_from `O'Brien` ) } )
    ?? ( pg_query_params c `SELECT id, name, created FROM t WHERE id = $1 OR name = $2` ps ) {
        T r → {
            : ~ i k 0
            ~ < k . r nrows {
                : i id ?? ( pg_row_i r k 0 ) { T x → x F → -1 }            // int4, binary
                : String name ?? ( pg_row_s r k 1 ) { T s → s F → ( string_from `NULL` ) }
                : i created ?? ( pg_row_ts r k 2 ) { T us → us F → 0 }     // µs since 1970, UTC
                = k + k 1
            }
        }
        F e → { ( nurl_eprint ( string_data ( pg_conn_lasterr c ) ) ) }   // `[SQLSTATE] message`
    }
    ^ 0  // c's last owner closes the connection
}
```

A pool, shared by fibers and threads (`stdlib/std/pool.nu`):

```
: ( Pool PgConn PgErr ) pool ( pg_pool_new `db` 5432 `me` `secret` `mydb` 3 @ PoolCfg { 1 16 5000 60000 } )
// PoolCfg { min max wait_ms idle_ms }
?? ( pg_pool_get pool ) {
    T g → { ( pg_query_params ( pooled_get [PgConn PgErr] g ) `UPDATE t SET n = n + 1 WHERE id = $1` ps ) }
    F e → { … }   // PgPoolTimeout after wait_ms, or the connect error
}                 // the connection goes back here
```

API:

```
( pg_connect host port user password database sslmode ) → !PgConn PgErr
( pg_query conn sql )                     → !PgResult PgErr   simple protocol, scripts
( pg_query_params conn sql params )       → !PgResult PgErr   ( Vec PgVal ) params
    PgVal: PgNull | PgInt i | PgFloat f | PgBool b | PgText String
         | PgBytes ( Vec u ) | PgTimestamp i (µs since 1970 UTC) | PgDate i (days since 1970)
( pg_result_nrows r ) ( pg_result_ncols r ) → i        (also the fields . r nrows / . r ncols)
( pg_result_col r col ) → String   ( pg_result_col_type r col ) → i (OID: PG_INT4, PG_TEXT, …)
( pg_result_col_index r name ) → ?i   ( pg_result_tag r ) → String   ( pg_result_affected r ) → i
( pg_row_i r row col )     → ?i        int2/4/8, oid (bool as 0/1), or a text cell holding one
( pg_row_f r row col )     → ?f        float4/8, integers, a numeric's text
( pg_row_b r row col )     → ?b
( pg_row_s r row col )     → ?String   any cell as text (binary ones rendered PostgreSQL's way;
                                       a timestamptz in UTC, `+00`)
( pg_row_bytes r row col ) → ?( Vec u ) bytea decoded (binary or `\x` text), a uuid's 16 bytes
( pg_row_ts r row col )    → ?i        timestamp / timestamptz / date as µs since 1970 UTC
( pg_row_date r row col )  → ?i        date (or a timestamp's day) as days since 1970
( pg_row_view r row col )  → ?( Slice u ) the raw cell, no copy
( pg_row_is_null r row col ) → b
( pg_result_cell r row col ) → String  ( pg_result_is_null r row col ) → b   (text view, as before)
( pg_conn_lasterr conn ) → String   ( pg_conn_sqlstate conn ) → String
( pg_conn_ok conn ) → b   ( pg_conn_txn_status conn ) → i   ( pg_conn_tls conn ) → i
( pg_conn_set_stmt_cache conn n ) → v   ( pg_conn_stmt_count conn ) → i
( pg_pool_new host port user password database sslmode cfg ) → ( Pool PgConn PgErr )
( pg_pool_get pool ) → !( Pooled PgConn PgErr ) PgErr   ( pg_conn_reset conn ) → b
( pg_result_free r ) → v   ( pg_close conn ) → v      early releases
```

A typed accessor answers `F` for NULL and for a value its type does not
hold (`pg_row_i` of a text that is no integer); `pg_row_is_null` tells the
two apart. Nothing is released by hand: a `PgConn` is a handle whose last
owner sends Terminate and closes the TLS session or socket, a `PgResult`
is a plain value, a pool checkout a guard. A `PgConn` may be shared by
threads and fibers (requests take turns on it); a pool is the way to run
them concurrently.

The protocol codec (`src/pgwire.nu`) holds no socket and no lock:
frontend messages are appended to a buffer, backend messages framed out of
one and folded by a collector into a result — the layer the connection
runs over, and the one a pipelining connection reuses.

## Limitations

* One request at a time per connection: requests from several fibers on
  one `PgConn` take turns (each holds it for its round trip) rather than
  being pipelined. Use a pool for concurrency.
* `SCRAM-SHA-256-PLUS` (channel binding) is not offered; SASLprep is the
  identity map (fine for the ASCII passwords used in practice).
* No `COPY`, `LISTEN`/`NOTIFY`, cursors / portal suspension (`Execute`
  fetches every row), or cancel requests.
* `verify-full` trusts the system store only (no `sslrootcert`).
* A binary timestamptz is rendered in UTC by `pg_row_s` (the session's
  `TimeZone` is not applied); numeric, interval, arrays, json and the
  other types come as text.
* TLS inherits the `tls` package's scope: TLS 1.3 (and 1.2 fallback), ECDHE
  over X25519 / P-256, RSA + ECDSA P-256/P-384 certificate chains.

## Tests

* `tests/wire_test.nu` — the codec, no server: messages byte for byte,
  framing, the collector over hand-built streams, every decoder and
  renderer.
* `tests/live_test.nu` — against a server named by `PSQL_TEST_PORT` (and
  `_HOST` / `_USER` / `_PASSWORD` / `_DB`): sslmode's verdicts and SCRAM,
  both protocols, typed round trips through real columns, the statement
  cache, errors and transactions, the pool on fibers and threads.
* `tests/live_smoke.sh` — both, the live one under AddressSanitizer; with
  no `PSQL_TEST_PORT` it starts a throwaway cluster (SCRAM, a self-signed
  certificate) from the PostgreSQL server binaries it finds.
