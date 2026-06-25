# psql — a pure-NURL PostgreSQL client

A PostgreSQL client written entirely in NURL: the **version-3 wire
protocol**, the **authentication** (trust / cleartext / MD5 /
SCRAM-SHA-256) and the **TLS transport** are all implemented from scratch,
with **no libpq and no OpenSSL**. A secure, authenticated connection works
on a machine that has nothing installed — the produced binary links
`libc` only, on Linux, macOS, the BSDs and Windows.

It builds on the [`tls`](../tls) package (a pure-NURL TLS 1.3 / 1.2 client)
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
* **Queries** — the simple query protocol (`Query` → `RowDescription` /
  `DataRow` / `CommandComplete`), with text-format decoding, NULL handling
  and backend `ErrorResponse` surfaced with its SQLSTATE and message.
* **A psql-style front end** — aligned result tables (numeric columns
  right-justified, NULLs blank, an `(N rows)` footer), backslash
  meta-commands, a multi-line REPL that accumulates a statement until its
  `;` terminator, TTY-only prompts and banner, and one-shot `-c`.

## sslmode

| mode          | code | behaviour                                            |
|---------------|------|------------------------------------------------------|
| `disable`     | 0    | plaintext only                                        |
| `prefer`      | 1    | TLS if the server offers it, no certificate check (default) |
| `require`     | 2    | TLS mandatory, no certificate check                   |
| `verify-full` | 3    | TLS mandatory + chain & hostname verified against the system trust store |

## Use as a command

```
nurlpkg install psql

psql -h localhost -p 5432 -U me -d mydb -c "select 1"
psql --sslmode require -U me -d mydb -c "select * from t"
psql "postgres://me:secret@db.example.com:5432/mydb?sslmode=verify-full" -c "select now()"
```

Run `psql --help` (or `-?`, or just `psql` with no arguments) for a usage
summary. The password is read from `$PGPASSWORD`; `-h/-p/-U/-d` fall back to
`$PGHOST/$PGPORT/$PGUSER/$PGDATABASE`. With no `-c`, it runs an interactive
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
    ?? ( pg_connect `localhost` 5432 `me` `secret` `mydb` 3 ) {
        F e → { ( nurl_eprint `connect failed\n` ) ^ 1 }
        T c → {
            ?? ( pg_query c `select id, name from t` ) {
                T r → {
                    // r.ncols / r.nrows; ( pg_result_cell r row col ),
                    // ( pg_result_is_null r row col ), ( pg_result_col r col )
                    ( pg_result_free r )
                }
                F _ → { ( nurl_eprint `query failed\n` ) }
            }
            ( pg_close c )
            ^ 0
        }
    }
}
```

API:

```
( pg_connect host port user password database sslmode ) → !*PgConn PgErr
( pg_query conn sql )                                    → !PgResult PgErr
( pg_result_col r col )                                  → String   // column name
( pg_result_cell r row col )                             → String   // text value
( pg_result_is_null r row col )                          → b
( pg_result_free r )                                     → v
( pg_close conn )                                        → v
```

On a `PgServerError` / `PgQuery` failure the backend message text is left
on `conn.lasterr`.

## Limitations

* Simple query protocol only (no prepared-statement / parameter binding
  yet); values are returned in their text representation.
* `SCRAM-SHA-256-PLUS` (channel binding) is not offered; SASLprep is the
  identity map (fine for the ASCII passwords used in practice).
* No connection pooling, `COPY`, `LISTEN`/`NOTIFY`, or binary result format.
* TLS inherits the `tls` package's scope: TLS 1.3 (and 1.2 fallback), ECDHE
  over X25519 / P-256, RSA + ECDSA P-256/P-384 certificate chains.
