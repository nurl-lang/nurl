# Known Limitations

Limitations and current scope boundaries of the compiler (`compiler/nurlc.nu`).
The authoritative grammar is [`spec/grammar.ebnf`](../spec/grammar.ebnf); the
normative language reference is [`docs/spec.md`](spec.md).

For active compiler quirks (binary `&` / `|` arity, bare `@-fn` closure
coercion, same-line parameter shadowing, ternary cascading, `: ~`
closure-borrow escape) see [`docs/GOTCHAS.md`](GOTCHAS.md). The memory model
and the borrow checker's not-yet-checked list live in
[`docs/MEMORY.md`](MEMORY.md).

## Type system

| Limitation | Workaround |
|---|---|
| Single-letter type keywords (`i u f b s v`) cannot be used as variable names with type inference | Use an explicit type annotation: `: i n expr` |

## Functions and calls

| Limitation | Workaround |
|---|---|
| Calls require explicit parens — `( f a b )` is the only call form; a bare identifier is always a name lookup, never a call | Wrap every callsite: `( puts s )` |
| Struct parameters are passed by **value** by default (C/Go/Zig semantics) — `= . p field val` inside the callee writes a local copy; the caller's struct is unchanged | Mark the parameter `inout` (`@ bump inout Counter c → v`) — an exclusive mutable borrow, the callee mutates the caller's binding in place (see [`docs/MEMORY.md`](MEMORY.md)). Or return the modified struct (`= c ( inc_returning c )`); or use a `*T` parameter; or wrap state in a single-handle struct (`{ ( Vec i ) slots }`) |
| No tail-call optimisation — deep recursion may stack-overflow | Use explicit loops (`~`) |
| Closures capture by value (snapshot at construction) by default. The `: ~` mutable-struct byref capture path (`stdlib/std/panic.nu` recover-with-typed-result) shares the caller's alloca — see [`docs/GOTCHAS.md` §5](GOTCHAS.md) for the lifetime rule | Use `: ~ MultiFieldStruct` for shared-mutation closures; for value semantics keep the binding immutable |

## Enums

| Limitation | Workaround |
|---|---|
| Enum variants with a named-struct payload require the struct to be declared **before** the enum in the same file — forward references are not supported | Order declarations: structs first, enums after |
| Pattern matching binds at most 3 payload variables per arm — variants with 4+ payloads cannot fully destructure in a single arm | Access additional payload fields via separate `.` extraction after matching |

## Imports

| Limitation | Workaround |
|---|---|
| `import_decl` is a static inline-include (like `#include`) — the imported file is compiled into the same LLVM module | Avoid importing files that define `main`; avoid circular imports |
| Import alias (`` $ `path` alias ``) rewrites top-level `@`-functions, struct/enum types, enum variants, and global `:` constants to `alias__name`. FFI decls (`& "lib" @ name`) and trait/impl methods are intentionally NOT renamed — FFI symbols resolve at the linker by literal C-ABI name, and trait methods are mangled by the impl-target type | Use `pub` to scope FFI declarations to the importing file if collision is a risk |
| `pub` visibility covers `@`-functions, struct/enum types, enum variants (inheriting their enum's flag), and global `:` constants. Files with no `pub` decl stay in legacy mode (everything public, backwards-compat). FFI and trait/impl decls accept `pub` forward-compat but do not enforce | Mark each cross-file API entry with `pub`; the diagnostic `private X 'Y' is not visible across files` points at the leaked-private use site |
| `$`-import dedup is keyed on the path string with a small normalisation (leading `./` is stripped). Symlink-equivalent paths still collide as separate imports | Stick to the project-root-relative form (`stdlib/foo.nu`, no `./` prefix) |

## Grammar

| Limitation | Workaround |
|---|---|
| Import is inline-include only: no namespaces. Alias rewriting covers `@`-functions, struct/enum types, enum variants, and global `:` constants; FFI decls and trait/impl methods are deliberately not renamed | Stick to a single canonical import path per file; prefix FFI names manually when collisions matter |
| **Every operator has fixed arity** (prefix notation has no closing token). `&` / `\|` / `^^` / `+` / `-` / `*` / `/` / `==` / `!=` / `<` / `>` / `<=` / `>=` / `<<` / `>>` are all **binary** (`OP A B`); `?` ternary is `? cond then else`; `^` / `!` / `~` are unary. A missing or extra operand silently consumes the next token, so the diagnostic can land on the following line | Count operands left-to-right when "unexpected token" fires on a line that looks fine. For n-ary `&`/`\|` chains write `& A & B C` or `& & & A B C D` (n−1 operators for n atoms); the compiler warns on the common `? & A B C D { … } { … }` shape |
| **`^` is the `return` keyword, not XOR** — but `^^` (two adjacent carets) **is** the native XOR operator. `^ a b` parses as `return (a b …)` | Use `^^` for XOR. The lexer pairs `^^` only when the carets are adjacent, so a stray space (`^ ^`) still means two returns |

## PostgreSQL — `stdlib/ext/postgres.nu`

Pure-NURL libpq FFI — no `runtime.c` changes. Build-time dependency:
`libpq-dev` (pkg-config). When absent, the compile-time FFI lib-check fires
with a clear "install libpq-dev" diagnostic, not a cryptic linker error. The
client is production-grade and covers the full protocol surface:

| Capability | Notes |
|---|---|
| Connection, escaping, exec, prepared statements, transactions | `pg_connect` / `_exec` / `_exec_params` / `_prepare` / `_exec_prepared` / `pg_begin` / `pg_commit` / `pg_rollback`. `Connection` / `PgResult` are value handles — `pg_close` each Connection and `pg_clear` each PgResult, even on Err arms. |
| Parameter binding (typed + NULL-aware) | `PgParams` builder + `pg_exec_params_b`; `pg_exec_params_opt` binds a `Vec ?String` (None = SQL NULL). |
| **Binary result protocol** | `pg_exec_params_binary` (resultFormat = 1) + `pg_get_i16_bin` / `_i32_bin` / `_i64_bin` / `_bool_bin` / `_f64_bin` decode network-byte-order cells. |
| **Asynchronous queries** | `pg_send` / `pg_send_params` / `pg_get_result` / `pg_await` + `pg_consume_input` / `pg_is_busy` / `pg_socket` / `pg_flush` / `pg_set_nonblocking`. |
| **LISTEN / NOTIFY** | `pg_listen` / `pg_notify_send` / `pg_notifies` / `pg_notify_free`. |
| **COPY** | `pg_copy_start` + `pg_put_copy_data` / `_str` / `_end` / `pg_get_copy_data`. |

See [`examples/pg_advanced.nu`](../examples/pg_advanced.nu) and
[`examples/psql.nu`](../examples/psql.nu).

> **Security:** TLS is not verified by default (libpq's `sslmode=prefer`).
> Put `sslmode=verify-full sslrootcert=…` in the conninfo for any non-local
> connection.

## SQLite — `stdlib/ext/sqlite.nu`

| Capability | Notes |
|---|---|
| **In-process SQLite** (`sqlite_open` / `_exec` / `_prepare` / `_bind_*` / `_step` / `_column_*` / `_finalize`) | Build-time dep: `libsqlite3-dev` (pkg-config). When absent, every call returns `SqliteUnsupported`. |
| `:memory:` and file-based databases | No network connection (use `http_post` for remote DBs). |
| `int64` and `text` binds + columns | `BLOB` and `double` deferred — stringify or hex-encode for now. |
| Transactions are pure SQL (`BEGIN` / `COMMIT` via `sqlite_exec`) | No dedicated transaction helper. |
| Statement lifecycle is caller-managed | `sqlite_prepare` → `sqlite_bind_*` → `sqlite_step` (loop) → `sqlite_finalize`. Reuse a Statement across bind sets with `sqlite_reset`. |

## Panic / recover — `stdlib/std/panic.nu`

| Capability | Notes |
|---|---|
| **`panic s msg → v`** | Halts execution. If a `recover` frame is active on this thread, longjmps to it; otherwise prints to stderr and aborts. Setjmp/longjmp-based — does NOT run destructors during unwind. |
| **`recover ( @ v ) closure → ! v PanicInfo`** | Run closure under a recover guard. Returns Ok(0) on normal completion, Err(PanicInfo) if the closure called `panic`. Use a `: ~`-mutable multi-field struct + byref-capture for typed returns. |
| Owned heap allocations made inside a recover scope **leak** if their auto-drop didn't fire | Recover is for crash mitigation, NOT routine error handling. Always prefer `! T E` + `\` for expected errors. |
| SIGSEGV / SIGFPE / SIGBUS / SIGABRT are NOT caught | Signal faults remain process-aborts. |
| HTTP server `handler` invocations are auto-recovered | A handler that panics → worker logs the message + returns 500 + keeps serving. |

## HTTPS / TLS

| Capability | Notes |
|---|---|
| **TLS server-side** via `tcp_listen_tls host port cert_path key_path → !TcpListener NetErr` | Build-time dependency: `libssl` (pkg-config). HttpServer integrates without code changes — swap `tcp_listen` for `tcp_listen_tls`. |
| **TLS client-side** via `tcp_connect_tls host port verify` | TLS client handshake with SNI; `verify` enables peer-certificate chain + host-name verification against the system trust store. The primitive behind the MQTT client and any outbound TLS. |
| TLS 1.2 minimum | TLS 1.0 / 1.1 / SSL 3.0 disabled in the SSL_CTX. |
| **SNI** (RFC 6066 §3) — `tcp_tls_add_sni listener hostname cert key` | Multi-tenant HTTPS — per-hostname cert/key pairs on one listener; handshake-time selection; no-match falls through to the default cert. |
| **ALPN** (RFC 7301) — `tcp_listen_tls_with_alpn`; `tcp_alpn_protocol conn` | Required by HTTP/2-over-TLS (RFC 9113 §3.3). |
| **Mutual TLS (mTLS)** — `tcp_tls_require_client_cert listener ca_bundle strict?`; `tcp_peer_cert_subject conn` | Strict (handshake fails without a cert) and opportunistic modes. |
| **Live cert reload** — `tcp_tls_reload listener hostname cert key` | Hot-swaps the SSL_CTX under a per-listener mutex; in-flight reads/writes on the old ctx survive until close. Standard Let's Encrypt-rotation use case. |
