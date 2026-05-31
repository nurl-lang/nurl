// stdlib/ext/postgres.nu — PostgreSQL client via direct libpq FFI.
//
// **Pure-NURL FFI** — every libpq symbol is declared with `& `pq` @ ...`
// directly in this file. There is no `runtime.c` bridge, in contrast
// to `stdlib/ext/sqlite.nu` which routes through `nurl_sqlite_*`
// runtime wrappers. The compiler's FFI-lib-check (`gen_ffi_decl`)
// scans every `&`-decl for a build-time sentinel `stdlib/runtime.pq`;
// absent libpq-dev → clear compile-time diagnostic, not a cryptic
// linker error.
//
// Production surface:
//
//   Connection
//     ( pg_connect s conninfo )            → Connection  (always a handle)
//     ( pg_ok Connection )                 → b           CONNECTION_OK?
//     ( pg_close Connection )              → v
//     ( pg_reset Connection )              → v           reconnect, same params
//     ( pg_err_msg Connection )            → String      OWNED, last error text
//     ( pg_server_version Connection )     → i           e.g. 160014 = 16.0.14
//     ( pg_db / pg_user / pg_host Conn )   → String      OWNED
//
//   Escaping (SQL-injection-safe literal/identifier quoting)
//     ( pg_escape_literal Connection s )   → String      OWNED, '…'-quoted
//     ( pg_escape_identifier Connection s )→ String      OWNED, "…"-quoted
//
//   Statement execution
//     ( pg_exec Connection s sql )                       → ! PgResult PgErr
//     ( pg_exec_params Connection s sql ( Vec String ) ) → ! PgResult PgErr  (all-text, no NULLs)
//     ( pg_exec_params_opt Conn s sql ( Vec ?String ) )  → ! PgResult PgErr  (option-typed; None = SQL NULL)
//     ( pg_exec_params_b Connection s sql PgParams )     → ! PgResult PgErr  (typed + NULL binds)
//     ( pg_prepare Conn s name s query i nparams )       → ! PgResult PgErr
//     ( pg_exec_prepared Conn s name ( Vec String ) )    → ! PgResult PgErr
//     ( pg_exec_prepared_b Conn s name PgParams )        → ! PgResult PgErr
//     ( pg_run Connection s sql )                        → ! i PgErr  (auto-clears, → affected rows)
//
//   Parameter builder (NULL-aware / typed)
//     ( pg_params i cap )                  → PgParams
//     ( pg_bind_text/_str/_int/_bool/_null PgParams … )  → v
//     ( pg_params_free PgParams )          → v   (or let an exec_*_b consume it)
//
//   Transactions (thin pg_run wrappers; auto-clear)
//     ( pg_begin / pg_commit / pg_rollback Connection )  → ! i PgErr
//
//   Result inspection
//     ( pg_result_status PgResult )        → i   raw libpq ExecStatusType
//     ( pg_result_is_ok PgResult )         → b
//     ( pg_result_err PgResult )           → String  OWNED  PQresultErrorMessage
//     ( pg_cmd_status PgResult )           → String  OWNED  e.g. "INSERT 0 3"
//     ( pg_affected PgResult )             → i       rows touched by INSERT/UPDATE/DELETE
//     ( pg_ntuples / pg_nfields PgResult ) → i
//     ( pg_field_name PgResult i col )     → String  OWNED
//     ( pg_fnumber PgResult s name )       → i       column index by name, -1 if absent
//     ( pg_ftype PgResult i col )          → i       column type OID
//     ( pg_get_value PgResult i row i col )→ String  OWNED
//     ( pg_get_is_null PgResult i row i col) → b
//     ( pg_get_opt PgResult i row i col )  → ?String  None on SQL NULL (OWNED on Some)
//     ( pg_get_opt_int PgResult i row i col) → ?i      None on SQL NULL
//     ( pg_get_int / pg_get_i64 … i col )  → i       text → integer
//     ( pg_get_f64 … )                     → f       text → double
//     ( pg_get_bool … )                    → b       't'/'f' → true/false
//     ( pg_clear PgResult )                → v
//
//   Binary result protocol (resultFormat = 1; text params, binary cells)
//     ( pg_exec_params_binary Conn s sql PgParams )      → ! PgResult PgErr
//     ( pg_get_i16_bin / _i32_bin / _i64_bin … i col )   → i   network-order
//     ( pg_get_bool_bin … )                → b
//     ( pg_get_f64_bin … )                 → f       IEEE-754 bit pattern
//     ( pg_get_length PgResult i row i col)→ i       cell byte length
//     ( pg_field_format PgResult i col )   → i       0 text / 1 binary
//     ( pg_binary_tuples PgResult )        → b
//
//   Asynchronous command processing (non-blocking dispatch)
//     ( pg_send Conn s sql )               → ! i PgErr
//     ( pg_send_params Conn s sql PgParams)→ ! i PgErr   CONSUMES params
//     ( pg_get_result Conn )               → ? PgResult  None when finished
//     ( pg_await Conn )                    → ! PgResult PgErr  final result
//     ( pg_consume_input Conn )            → ! i PgErr
//     ( pg_is_busy Conn ) / ( pg_socket Conn ) / ( pg_flush Conn )
//     ( pg_set_nonblocking Conn b ) / ( pg_is_nonblocking Conn )
//
//   LISTEN / NOTIFY (async pub/sub)
//     ( pg_listen Conn s channel )         → ! i PgErr      LISTEN channel
//     ( pg_notify_send Conn s channel s payload ) → ! i PgErr
//     ( pg_notifies Conn )                 → ? PgNotify  (after consume_input)
//     ( pg_notify_free PgNotify )          → v           frees owned Strings
//       PgNotify fields: relname (String), be_pid (i), extra (String)
//
//   COPY (bulk row streaming)
//     ( pg_copy_start Conn s sql )         → ! i PgErr   accepts COPY_IN/OUT
//     ( pg_put_copy_data Conn s buf i n )  → ! i PgErr   one chunk
//     ( pg_put_copy_str Conn String row )  → ! i PgErr   one text row
//     ( pg_put_copy_end Conn )             → ! i PgErr   finish FROM STDIN
//     ( pg_get_copy_data Conn )            → ? String    None at end; OWNED
//
// Memory model:
//
//   * `pg_connect` ALWAYS returns a Connection handle — libpq's
//     `PQconnectdb` returns a non-NULL `PGconn*` even on failure so the
//     caller can inspect `pg_err_msg`. ALWAYS `pg_close` it, healthy or
//     not, to release the underlying struct.
//   * `pg_exec` family return an OWNED PgResult on the T arm; the caller
//     MUST `pg_clear` it (`PQclear`). On the F arm there is nothing to
//     clear — the failed result is cleared internally. Read the error
//     text with `pg_err_msg` on the connection.
//   * `pg_exec_params` / `pg_exec_params_opt` / `pg_exec_prepared`
//     CONSUME their params Vec — they free every element String and the
//     Vec backing after the exec. Do NOT touch or free the Vec afterward.
//   * `pg_get_value` / `pg_field_name` / `pg_err_msg` / escape / info
//     getters return OWNED Strings (copied via `string_from` because
//     libpq's pointers become invalid after `PQclear` / `PQfinish`).
//
// Security:
//
//   * TLS is NOT verified by default — see `pg_connect`. Put
//     `sslmode=verify-full sslrootcert=…` in the conninfo for any
//     non-local connection, or the link is MITM-able.
//   * Pass VALUES as bound parameters (`PgParams` / `pg_exec_params_b` /
//     `pg_exec_prepared_b`), never string-concatenated into the SQL.
//     IDENTIFIERS (table / column / channel names) cannot be bound — quote
//     them with `pg_escape_identifier` (as `pg_listen` does). String
//     LITERALS, if you truly must inline them, go through
//     `pg_escape_literal`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// Errors — `PgErr` is a lightweight code; the human-readable text is
// always retrievable from the connection via `pg_err_msg` (libpq copies
// the failing result's message into the connection's error buffer), so
// the enum carries no owned payload to free.
: | PgErr {
    PgConnectFailed  // PQstatus(conn) != CONNECTION_OK
    PgExecFailed  // PQresultStatus not COMMAND_OK / TUPLES_OK
    PgNullResult  // PQexec / PQexecParams returned NULL (OOM / fatal)
    PgOther  // anything else
}

: Connection { s raw }
: PgResult { s raw }

@ pg_err_name PgErr e → s {
    ^ ?? e {
        PgConnectFailed → `PgConnectFailed`
        PgExecFailed → `PgExecFailed`
        PgNullResult → `PgNullResult`
        PgOther → `PgOther`
    }
}

// ── FFI declarations ──────────────────────────────────────────────
//
// Every NURL `s` parameter is i8* in LLVM, the exact shape libpq wants
// for `const char *` arguments AND for returning `PGconn*` / `PGresult*`
// opaque handles — threaded through NURL Connection / PgResult structs
// as `s raw`.

& `pq` @ PQconnectdb s conninfo → s
& `pq` @ PQfinish s conn → v
& `pq` @ PQreset s conn → v
& `pq` @ PQstatus s conn → i32
& `pq` @ PQerrorMessage s conn → s
& `pq` @ PQserverVersion s conn → i32
& `pq` @ PQdb s conn → s
& `pq` @ PQuser s conn → s
& `pq` @ PQhost s conn → s

& `pq` @ PQescapeLiteral s conn s str i len → s
& `pq` @ PQescapeIdentifier s conn s str i len → s
& `pq` @ PQfreemem s ptr → v

& `pq` @ PQexec s conn s sql → s
// Parameterised exec — text format only (paramTypes / paramLengths /
// paramFormats / resultFormat all 0/NULL so libpq treats every param as
// a NUL-terminated UTF-8 string and returns text rows). A NULL entry in
// the values array is sent as SQL NULL.
& `pq` @ PQexecParams s conn s sql i32 n_params *u types **u values *i32 lens *i32 fmts i32 res_fmt → s
& `pq` @ PQprepare s conn s stmt s query i32 n_params *u types → s
& `pq` @ PQexecPrepared s conn s stmt i32 n_params **u values *i32 lens *i32 fmts i32 res_fmt → s

& `pq` @ PQclear s res → v
& `pq` @ PQresultStatus s res → i32
& `pq` @ PQresultErrorMessage s res → s
& `pq` @ PQcmdStatus s res → s
& `pq` @ PQcmdTuples s res → s
& `pq` @ PQntuples s res → i32
& `pq` @ PQnfields s res → i32
& `pq` @ PQfname s res i32 col → s
& `pq` @ PQfnumber s res s name → i32
& `pq` @ PQftype s res i32 col → u32
& `pq` @ PQgetvalue s res i32 row i32 col → s
& `pq` @ PQgetisnull s res i32 row i32 col → i32

// Binary protocol — request binary result columns (resultFormat = 1) and
// read raw network-byte-order cell bytes. PQgetvalue still returns the
// cell pointer, but for a binary column it points at `PQgetlength` bytes
// of big-endian binary, not a NUL-terminated text rendering.
& `pq` @ PQgetlength s res i32 row i32 col → i32
& `pq` @ PQfformat s res i32 col → i32  // 0 = text column, 1 = binary
& `pq` @ PQbinaryTuples s res → i32

// Asynchronous command processing — dispatch a command without blocking
// on its result, then collect results with PQgetResult (NULL = done).
// PQconsumeInput / PQisBusy let an event loop poll PQsocket for readiness.
& `pq` @ PQsendQuery s conn s sql → i32
& `pq` @ PQsendQueryParams s conn s sql i32 n_params *u types **u values *i32 lens *i32 fmts i32 res_fmt → i32
& `pq` @ PQsendPrepare s conn s stmt s query i32 n_params *u types → i32
& `pq` @ PQsendQueryPrepared s conn s stmt i32 n_params **u values *i32 lens *i32 fmts i32 res_fmt → i32
& `pq` @ PQgetResult s conn → s  // PGresult* or NULL when no more results
& `pq` @ PQconsumeInput s conn → i32  // 1 = ok, 0 = error
& `pq` @ PQisBusy s conn → i32  // 1 = a PQgetResult would block
& `pq` @ PQsetnonblocking s conn i32 arg → i32
& `pq` @ PQisnonblocking s conn → i32
& `pq` @ PQflush s conn → i32  // 0 = sent, 1 = more queued, -1 = error
& `pq` @ PQsocket s conn → i32  // file descriptor, -1 if no connection

// LISTEN / NOTIFY — PQnotifies pops the next buffered async notification
// (a PGnotify*) after PQconsumeInput has drained the socket; NULL when
// none are pending. The struct is `{ char *relname; int be_pid;
// char *extra; … }` — freed with PQfreemem.
& `pq` @ PQnotifies s conn → s

// COPY — bulk row streaming. PQputCopyData / PQputCopyEnd feed a
// COPY FROM STDIN; PQgetCopyData pulls rows from a COPY TO STDOUT.
& `pq` @ PQputCopyData s conn s buffer i32 nbytes → i32  // 1 ok, 0 full, -1 err
& `pq` @ PQputCopyEnd s conn s errormsg → i32  // errormsg NULL = success
& `pq` @ PQgetCopyData s conn **u buffer i32 async → i32  // >0 len, -1 done, -2 err

// PQstatus:        CONNECTION_OK = 0,  CONNECTION_BAD = 1
// PQresultStatus:  PGRES_COMMAND_OK = 1,  PGRES_TUPLES_OK = 2,
//                  PGRES_FATAL_ERROR = 7, …

// ── Connection lifecycle ──────────────────────────────────────────

// Open a connection. ALWAYS returns a handle (even on failure) so the
// caller can read `pg_err_msg`. Check `pg_ok`; always `pg_close`.
//
// ⚠ SECURITY — TLS is NOT verified by default. `conninfo` is passed
// verbatim to libpq, whose default `sslmode=prefer` uses TLS only if the
// server offers it, SILENTLY falls back to plaintext otherwise, and NEVER
// verifies the server certificate. Over an untrusted network that is
// MITM-able. For any non-local connection put
//   sslmode=verify-full sslrootcert=/path/to/ca.crt
// in `conninfo` (verify-full also checks the host name against the cert).
// `verify-full` is the only mode that authenticates the server; `require`
// encrypts but still trusts any certificate. Unix-socket / trusted-LAN
// connections legitimately need no TLS — hence this is a caller decision,
// not a forced default (forcing verify-full would break those).
@ pg_connect s conninfo → Connection {
    : s raw ( PQconnectdb conninfo )
    ^ @ Connection { raw }
}

@ pg_ok Connection c → b {
    : i32 st ( PQstatus . c raw )
    ^ == # i st 0
}

@ pg_close Connection c → v {
    ( PQfinish . c raw )
}

// Reset (reconnect) using the original connection parameters. Recovers
// a connection broken by a server restart or network blip.
@ pg_reset Connection c → v {
    ( PQreset . c raw )
}

// Most recent error text. OWNED String — caller frees with `string_free`.
// Empty on a healthy connection.
@ pg_err_msg Connection c → String {
    ^ ( string_from ( PQerrorMessage . c raw ) )
}

@ pg_server_version Connection c → i {
    ^ # i ( PQserverVersion . c raw )
}

@ pg_db Connection c → String {
    ^ ( string_from ( PQdb . c raw ) )
}

@ pg_user Connection c → String {
    ^ ( string_from ( PQuser . c raw ) )
}

@ pg_host Connection c → String {
    ^ ( string_from ( PQhost . c raw ) )
}

// ── Escaping ──────────────────────────────────────────────────────
//
// PQescapeLiteral / PQescapeIdentifier return a freshly-malloc'd,
// already-quoted C string we must copy then release with PQfreemem.
//
// NULL return (OOM, or invalid UTF-8 for the connection's encoding)
// surfaces here as an EMPTY String, NOT an error value. This is safe
// against injection — an empty literal/identifier spliced into SQL yields
// a syntax error, never an unescaped value — but it IS a silent failure:
// if you must distinguish "escaped to empty" from "escape failed", check
// the connection with pg_err_msg, or prefer bound parameters (PgParams /
// pg_exec_params_b) for values, which never need manual escaping.

@ pg_escape_literal Connection c s str → String {
    : i len ( nurl_str_len str )
    : s raw ( PQescapeLiteral . c raw str len )
    ? == raw 0 { ^ ( string_from `` ) } {}
    : String out ( string_from raw )
    ( PQfreemem raw )
    ^ out
}

@ pg_escape_identifier Connection c s str → String {
    : i len ( nurl_str_len str )
    : s raw ( PQescapeIdentifier . c raw str len )
    ? == raw 0 { ^ ( string_from `` ) } {}
    : String out ( string_from raw )
    ( PQfreemem raw )
    ^ out
}

// ── Result construction helper ────────────────────────────────────
//
// Wrap a raw PGresult* from any of the exec entry points: NULL → Err
// PgNullResult; status COMMAND_OK/TUPLES_OK → Ok; otherwise clear and
// Err PgExecFailed (the message rides the connection's error buffer).
@ __pg_wrap_result s raw → !PgResult PgErr {
    ? == raw 0 {
        ^ @ !PgResult PgErr { F # PgErr PgNullResult }
    } {}
    : PgResult r @ PgResult { raw }
    ? ( pg_result_is_ok r ) {
        ^ @ !PgResult PgErr { T r }
    } {}
    ( pg_clear r )
    ^ @ !PgResult PgErr { F # PgErr PgExecFailed }
}

// ── Statement execution ──────────────────────────────────────────

@ pg_exec Connection c s sql → !PgResult PgErr {
    ^ ( __pg_wrap_result ( PQexec . c raw sql ) )
}

// Parameterised exec — every parameter is a NUL-terminated text-format
// string. CONSUMES `params`: the element Strings and the Vec backing are
// freed after the exec (libpq has copied the values by then).
@ pg_exec_params Connection c s sql ( Vec String ) params → !PgResult PgErr {
    : i n ( vec_len [String] params )
    // Parallel `char *` array. 8 bytes per pointer; libpq only reads it.
    : s vals ( nurl_alloc * n 8 )
    : ~ i k 0
    ~ < k n {
        : ?String pk ( vec_get [String] params k )
        ?? pk {
            // nurl_poke uses SLOT indexing (×8 internally) — pass `k`,
            // NOT `k * 8`. Borrow string_data; do NOT free yet.
            T sv → ( nurl_poke vals k # i ( string_data sv ) )
            F _ → ( nurl_poke vals k 0 )
        }
        = k + k 1
    }
    : !PgResult PgErr res ( __pg_exec_params_raw c sql n vals )
    ( nurl_free vals )
    // Exec done — libpq copied the params, safe to release the Strings.
    ( vec_free_with [String] params \ String s → v { ( string_free s ) } )
    ^ res
}

// Option-typed NULL-aware parameterised exec. `params` is a `Vec ?String`
// where a `T text` element binds that text and an `F` (None) element
// binds SQL NULL — the idiomatic way to express "this column may be NULL"
// with the language's own option type. CONSUMES `params` (frees every
// Some-String and the Vec backing after the exec).
//
//   : ( Vec ?String ) ps ( vec_with_cap [?String] 2 )
//   ( vec_push [?String] ps @ ?String { T ( string_from `alice` ) } )
//   ( vec_push [?String] ps @ ?String { F # String 0 } )   // → SQL NULL
//   : !PgResult PgErr r ( pg_exec_params_opt c `INSERT … VALUES ($1,$2)` ps )
@ pg_exec_params_opt Connection c s sql ( Vec ?String ) params → !PgResult PgErr {
    : i n ( vec_len [?String] params )
    : s vals ( nurl_alloc * ? > n 0 n 1 8 )
    : ~ i k 0
    ~ < k n {
        // vec_get over a `Vec ?String` yields `??String`: the outer
        // option is the bounds check, the inner is the value-or-NULL.
        : ??String pk ( vec_get [?String] params k )
        ?? pk {
            T inner → {
                ?? inner {
                    T sv → ( nurl_poke vals k # i ( string_data sv ) )
                    F _ → ( nurl_poke vals k 0 )
                }
            }
            F _ → ( nurl_poke vals k 0 )
        }
        = k + k 1
    }
    : !PgResult PgErr res ( __pg_exec_params_raw c sql n vals )
    ( nurl_free vals )
    ( vec_free_with [?String] params \ ?String o → v {
        ?? o { T sv → ( string_free sv )  F _ → {} }
    } )
    ^ res
}

// ── PgParams: NULL-aware / typed parameter builder ───────────────
//
// libpq binds parameters through a parallel `char**` array where a NULL
// pointer means SQL NULL. PgParams is that array, built incrementally
// with typed binders — the production way to pass NULLs and non-string
// values (mirrors libpq's paramValues, pgx, and tokio-postgres). Each
// slot keeps its text in `texts` and a `nulls` flag (1 = SQL NULL, the
// text slot then holds a throwaway empty String). CONSUMED by
// `pg_exec_params_b` / `pg_exec_prepared_b`, which free it after exec.
//
//   : PgParams ps ( pg_params 3 )
//   ( pg_bind_text ps `alice` )
//   ( pg_bind_int  ps 42 )
//   ( pg_bind_null ps )
//   : !PgResult PgErr r ( pg_exec_params_b c `INSERT … VALUES ($1,$2,$3)` ps )
: PgParams { ( Vec String ) texts ( Vec i ) nulls }

@ pg_params i cap → PgParams {
    : i want ? > cap 0 cap 1
    ^ @ PgParams { ( vec_with_cap [String] want ) ( vec_with_cap [i] want ) }
}

// Bind a borrowed C string (copied into an owned slot).
@ pg_bind_text PgParams p s val → v {
    ( vec_push [String] . p texts ( string_from val ) )
    ( vec_push [i] . p nulls 0 )
}

// Bind an already-owned String (PgParams takes ownership).
@ pg_bind_str PgParams p String val → v {
    ( vec_push [String] . p texts val )
    ( vec_push [i] . p nulls 0 )
}

@ pg_bind_int PgParams p i val → v {
    ( vec_push [String] . p texts ( string_from ( nurl_str_int val ) ) )
    ( vec_push [i] . p nulls 0 )
}

// PostgreSQL accepts 't'/'f' (and 'true'/'false') as boolean literals.
@ pg_bind_bool PgParams p b val → v {
    ( vec_push [String] . p texts ( string_from ? val `t` `f` ) )
    ( vec_push [i] . p nulls 0 )
}

@ pg_bind_null PgParams p → v {
    ( vec_push [String] . p texts ( string_new ) )
    ( vec_push [i] . p nulls 1 )
}

@ pg_params_len PgParams p → i {
    ^ ( vec_len [String] . p texts )
}

@ pg_params_free PgParams p → v {
    ( vec_free_with [String] . p texts \ String s → v { ( string_free s ) } )
    ( vec_free [i] . p nulls )
}

// Build the borrowed `char**` array from a PgParams. NULL slots become a
// 0 pointer (SQL NULL); the text pointers stay valid until the params are
// freed, which the exec wrappers do only after PQexecParams returns.
@ __pg_params_vals PgParams p → s {
    : ( Vec String ) texts . p texts
    : ( Vec i ) nulls . p nulls
    : i n ( vec_len [String] texts )
    : s vals ( nurl_alloc * ? > n 0 n 1 8 )
    : ~ i k 0
    ~ < k n {
        : ?i fl ( vec_get [i] nulls k )
        : ~ i is_null 0
        ?? fl { T x → = is_null x  F _ → {} }
        ? != is_null 0 {
            ( nurl_poke vals k 0 )
        } {
            ?? ( vec_get [String] texts k ) {
                T sv → ( nurl_poke vals k # i ( string_data sv ) )
                F _ → ( nurl_poke vals k 0 )
            }
        }
        = k + k 1
    }
    ^ vals
}

// PgParams-driven parameterised exec. CONSUMES `p`.
@ pg_exec_params_b Connection c s sql PgParams p → !PgResult PgErr {
    : i n ( pg_params_len p )
    : s vals ( __pg_params_vals p )
    : !PgResult PgErr res ( __pg_exec_params_raw c sql n vals )
    ( nurl_free vals )
    ( pg_params_free p )
    ^ res
}

// PgParams-driven prepared-statement exec. CONSUMES `p`.
@ pg_exec_prepared_b Connection c s name PgParams p → !PgResult PgErr {
    : i n ( pg_params_len p )
    : s vals ( __pg_params_vals p )
    : **u vptr # **u vals
    : *i32 lens # *i32 0
    : *i32 fmts # *i32 0
    : i32 nn # i32 n
    : i32 zero # i32 0
    : !PgResult PgErr res ( __pg_wrap_result ( PQexecPrepared . c raw name nn vptr lens fmts zero ) )
    ( nurl_free vals )
    ( pg_params_free p )
    ^ res
}

// Shared PQexecParams trampoline — `vals` is the prepared `char**`.
@ __pg_exec_params_raw Connection c s sql i n s vals → !PgResult PgErr {
    : **u vptr # **u vals
    : *u types # *u 0
    : *i32 lens # *i32 0
    : *i32 fmts # *i32 0
    : i32 nn # i32 n
    : i32 zero # i32 0
    ^ ( __pg_wrap_result ( PQexecParams . c raw sql nn types vptr lens fmts zero ) )
}

// Server-side prepared statement. `name` is the statement name (use
// `` for the unnamed statement). `nparams` is the placeholder count;
// types are inferred by the server (paramTypes = NULL). Returns a
// COMMAND_OK PgResult on success — `pg_clear` it.
@ pg_prepare Connection c s name s query i nparams → !PgResult PgErr {
    : i32 np # i32 nparams
    : *u types # *u 0
    ^ ( __pg_wrap_result ( PQprepare . c raw name query np types ) )
}

// Execute a previously-prepared statement by name. CONSUMES `params`.
@ pg_exec_prepared Connection c s name ( Vec String ) params → !PgResult PgErr {
    : i n ( vec_len [String] params )
    : s vals ( nurl_alloc * n 8 )
    : ~ i k 0
    ~ < k n {
        : ?String pk ( vec_get [String] params k )
        ?? pk {
            T sv → ( nurl_poke vals k # i ( string_data sv ) )
            F _ → ( nurl_poke vals k 0 )
        }
        = k + k 1
    }
    : **u vptr # **u vals
    : *i32 lens # *i32 0
    : *i32 fmts # *i32 0
    : i32 nn # i32 n
    : i32 zero # i32 0
    : !PgResult PgErr res ( __pg_wrap_result ( PQexecPrepared . c raw name nn vptr lens fmts zero ) )
    ( nurl_free vals )
    ( vec_free_with [String] params \ String s → v { ( string_free s ) } )
    ^ res
}

// Fire-and-forget exec for DDL/DML — runs `sql`, auto-clears the result,
// and yields the number of rows affected (0 for DDL). The error text is
// on the connection via `pg_err_msg`.
@ pg_run Connection c s sql → !i PgErr {
    : !PgResult PgErr rr ( pg_exec c sql )
    ?? rr {
        F e → ^ @ !i PgErr { F e }
        T r → {
            : i n ( pg_affected r )
            ( pg_clear r )
            ^ @ !i PgErr { T n }
        }
    }
}

// ── Transactions ─────────────────────────────────────────────────

@ pg_begin Connection c → !i PgErr {
    ^ ( pg_run c `BEGIN` )
}

@ pg_commit Connection c → !i PgErr {
    ^ ( pg_run c `COMMIT` )
}

@ pg_rollback Connection c → !i PgErr {
    ^ ( pg_run c `ROLLBACK` )
}

// ── Result inspection ────────────────────────────────────────────

@ pg_result_status PgResult r → i {
    ^ # i ( PQresultStatus . r raw )
}

@ pg_result_is_ok PgResult r → b {
    : i st ( pg_result_status r )
    ^ | == st 1 == st 2
}

// PQresultErrorMessage — error text tied to this specific result. OWNED.
@ pg_result_err PgResult r → String {
    ^ ( string_from ( PQresultErrorMessage . r raw ) )
}

// Command tag, e.g. "INSERT 0 3", "UPDATE 5", "CREATE TABLE". OWNED.
@ pg_cmd_status PgResult r → String {
    ^ ( string_from ( PQcmdStatus . r raw ) )
}

// Rows affected by the INSERT/UPDATE/DELETE/MOVE/FETCH that produced
// this result. 0 for statements that touch no rows (DDL, SELECT).
@ pg_affected PgResult r → i {
    ^ ( nurl_str_to_int ( PQcmdTuples . r raw ) )
}

@ pg_ntuples PgResult r → i {
    ^ # i ( PQntuples . r raw )
}

@ pg_nfields PgResult r → i {
    ^ # i ( PQnfields . r raw )
}

@ pg_field_name PgResult r i col → String {
    : i32 c32 # i32 col
    ^ ( string_from ( PQfname . r raw c32 ) )
}

// Column index for `name`, or -1 if there is no such column.
@ pg_fnumber PgResult r s name → i {
    ^ # i ( PQfnumber . r raw name )
}

// Column type OID (pg_type.oid). 23 = int4, 25 = text, 16 = bool, …
@ pg_ftype PgResult r i col → i {
    : i32 c32 # i32 col
    ^ # i ( PQftype . r raw c32 )
}

@ pg_get_value PgResult r i row i col → String {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    ^ ( string_from ( PQgetvalue . r raw r32 c32 ) )
}

@ pg_get_is_null PgResult r i row i col → b {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    ^ != 0 # i ( PQgetisnull . r raw r32 c32 )
}

// Option-typed cell read: `F` (None) for a SQL NULL, `T text` (an OWNED
// String the caller frees) otherwise. Lets a caller handle nullability
// with the language's own option type:
//
//   ?? ( pg_get_opt r row col ) { T s → … ( string_free s )  F _ → … }
@ pg_get_opt PgResult r i row i col → ?String {
    ? ( pg_get_is_null r row col ) { ^ @ ?String { F # String 0 } } {}
    ^ @ ?String { T ( pg_get_value r row col ) }
}

// Option-typed integer read: `F` for SQL NULL, `T n` otherwise.
@ pg_get_opt_int PgResult r i row i col → ?i {
    ? ( pg_get_is_null r row col ) { ^ @ ?i { F # i 0 } } {}
    ^ @ ?i { T ( pg_get_int r row col ) }
}

// Typed accessors — read the text cell directly (no owned-String copy)
// and parse. NULL / empty cells parse to 0 / 0.0 / false.
@ pg_get_int PgResult r i row i col → i {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    ^ ( nurl_str_to_int ( PQgetvalue . r raw r32 c32 ) )
}

@ pg_get_f64 PgResult r i row i col → f {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    ^ ( nurl_str_to_float ( PQgetvalue . r raw r32 c32 ) )
}

// PostgreSQL renders boolean as the single byte 't' / 'f'.
// PostgreSQL renders boolean text as a single byte 't' / 'f'. A SQL NULL
// (or out-of-range row/col) gives an empty cell → not 't' → false. The
// explicit NULL guard avoids relying on libpq always handing back a
// non-NULL pointer (and keeps nurl_str_get's strlen off a NULL).
@ pg_get_bool PgResult r i row i col → b {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    : s v ( PQgetvalue . r raw r32 c32 )
    ? == # i v 0 { ^ F } {}
    ^ == ( nurl_str_get v 0 ) 116
}

@ pg_clear PgResult r → v {
    ( PQclear . r raw )
}

// ══════════════════════════════════════════════════════════════════
//  Binary result protocol
// ══════════════════════════════════════════════════════════════════
//
// Parameters are still sent as text (the common pattern), but every
// result column is requested in binary (resultFormat = 1): each cell is
// raw big-endian wire bytes rather than a text rendering. Decode them
// with the `pg_get_*_bin` accessors below. CONSUMES `p`.
//
//   : PgParams ps ( pg_params 1 )
//   ( pg_bind_int ps 41 )
//   : !PgResult PgErr rr ( pg_exec_params_binary c `SELECT $1::int8 + 1` ps )
//   ?? rr { T r → { : i v ( pg_get_i64_bin r 0 0 )  ( pg_clear r ) }  F e → {} }
@ pg_exec_params_binary Connection c s sql PgParams p → !PgResult PgErr {
    : i n ( pg_params_len p )
    : s vals ( __pg_params_vals p )
    : **u vptr # **u vals
    : *u types # *u 0
    : *i32 lens # *i32 0
    : *i32 fmts # *i32 0
    : i32 nn # i32 n
    : i32 one # i32 1
    : !PgResult PgErr res ( __pg_wrap_result ( PQexecParams . c raw sql nn types vptr lens fmts one ) )
    ( nurl_free vals )
    ( pg_params_free p )
    ^ res
}

// Byte length of a result cell (text or binary).
@ pg_get_length PgResult r i row i col → i {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    ^ # i ( PQgetlength . r raw r32 c32 )
}

// Wire format of a column: 0 = text, 1 = binary.
@ pg_field_format PgResult r i col → i {
    ^ # i ( PQfformat . r raw # i32 col )
}

// True if the result's columns are all binary-format.
@ pg_binary_tuples PgResult r → b {
    ^ != 0 # i ( PQbinaryTuples . r raw )
}

// Read `nbytes` big-endian (network order) bytes from a raw cell pointer
// into an unsigned i64 accumulator. PostgreSQL sends binary integers and
// the IEEE-754 bit pattern of float8 in network byte order.
@ __pg_be_read s ptr i nbytes → i {
    ? == # i ptr 0 { ^ 0 } {}
    : *u p # *u ptr
    : ~ i acc 0
    : ~ i k 0
    ~ < k nbytes {
        : u b . p k
        = acc | << acc 8 & # i b 255
        = k + k 1
    }
    ^ acc
}

// Bounds-checked binary cell pointer. Returns the raw cell pointer ONLY
// when the cell holds at least `need` bytes; otherwise NULL (# s 0), which
// __pg_be_read reads as 0. This guards against reading past a cell that is
// shorter than the accessor's fixed width — e.g. a binary SQL NULL (0
// bytes), or calling pg_get_i64_bin (8 bytes) on an int4 column (4 bytes).
// Without it the decoder walked into adjacent libpq buffer memory (an
// out-of-bounds read).
@ __pg_bin_ptr PgResult r i row i col i need → s {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    ? < # i ( PQgetlength . r raw r32 c32 ) need { ^ # s 0 } {}
    ^ ( PQgetvalue . r raw r32 c32 )
}

// int2 / smallint — 2-byte big-endian, sign-extended.
@ pg_get_i16_bin PgResult r i row i col → i {
    : i v ( __pg_be_read ( __pg_bin_ptr r row col 2 ) 2 )
    ^ ? >= v 32768 - v 65536 v
}

// int4 / integer — 4-byte big-endian, sign-extended.
@ pg_get_i32_bin PgResult r i row i col → i {
    : i v ( __pg_be_read ( __pg_bin_ptr r row col 4 ) 4 )
    ^ ? >= v 2147483648 - v 4294967296 v
}

// int8 / bigint — 8-byte big-endian.
@ pg_get_i64_bin PgResult r i row i col → i {
    ^ ( __pg_be_read ( __pg_bin_ptr r row col 8 ) 8 )
}

// boolean — single binary byte, non-zero = true.
@ pg_get_bool_bin PgResult r i row i col → b {
    ^ != 0 ( __pg_be_read ( __pg_bin_ptr r row col 1 ) 1 )
}

// float8 / double precision — 8-byte big-endian IEEE-754, reinterpreted
// from its bit pattern (not a numeric int→float conversion). A short /
// NULL cell yields 0.0 via the bounds-checked pointer.
@ pg_get_f64_bin PgResult r i row i col → f {
    : i bits ( __pg_be_read ( __pg_bin_ptr r row col 8 ) 8 )
    : s buf ( nurl_alloc 8 )
    ( nurl_poke buf 0 bits )
    : *f fp # *f buf
    : f out . fp 0
    ( nurl_free buf )
    ^ out
}

// ══════════════════════════════════════════════════════════════════
//  Asynchronous command processing
// ══════════════════════════════════════════════════════════════════
//
// `pg_send` / `pg_send_params` dispatch a command without blocking on its
// reply. Collect results with `pg_get_result` (None = the command is
// finished) — or just call `pg_await` to block for the final result.
// `pg_socket` + `pg_consume_input` + `pg_is_busy` integrate with an event
// loop: wait for the socket to be readable, consume input, and only call
// `pg_get_result` while `pg_is_busy` is false. ALWAYS drain every result
// (loop to None) before the next command on the same connection.

@ pg_send Connection c s sql → !i PgErr {
    ? == 0 # i ( PQsendQuery . c raw sql ) {
        ^ @ !i PgErr { F # PgErr PgExecFailed }
    } {}
    ^ @ !i PgErr { T 1 }
}

@ pg_send_params Connection c s sql PgParams p → !i PgErr {
    : i n ( pg_params_len p )
    : s vals ( __pg_params_vals p )
    : **u vptr # **u vals
    : *u types # *u 0
    : *i32 lens # *i32 0
    : *i32 fmts # *i32 0
    : i32 nn # i32 n
    : i32 zero # i32 0
    : i rc # i ( PQsendQueryParams . c raw sql nn types vptr lens fmts zero )
    ( nurl_free vals )
    ( pg_params_free p )
    ? == 0 rc { ^ @ !i PgErr { F # PgErr PgExecFailed } } {}
    ^ @ !i PgErr { T 1 }
}

// Drain buffered server data into libpq (1 = ok). Call before
// `pg_is_busy` / `pg_notifies` when the socket signals readable.
@ pg_consume_input Connection c → !i PgErr {
    ? == 0 # i ( PQconsumeInput . c raw ) {
        ^ @ !i PgErr { F # PgErr PgExecFailed }
    } {}
    ^ @ !i PgErr { T 1 }
}

// True if a `pg_get_result` would block (more input needed first).
@ pg_is_busy Connection c → b {
    ^ != 0 # i ( PQisBusy . c raw )
}

// Underlying socket fd for select/poll, or -1 if not connected.
@ pg_socket Connection c → i {
    ^ # i ( PQsocket . c raw )
}

// Toggle non-blocking send mode. In non-blocking mode `pg_flush` must be
// pumped until it returns 0.
@ pg_set_nonblocking Connection c b on → !i PgErr {
    : i32 arg # i32 ? on 1 0
    ? == -1 # i ( PQsetnonblocking . c raw arg ) {
        ^ @ !i PgErr { F # PgErr PgExecFailed }
    } {}
    ^ @ !i PgErr { T 1 }
}

@ pg_is_nonblocking Connection c → b {
    ^ != 0 # i ( PQisnonblocking . c raw )
}

// Flush queued output. 0 = all sent, 1 = data still queued, -1 = error.
@ pg_flush Connection c → i {
    ^ # i ( PQflush . c raw )
}

// Pop the next result of an in-flight async command. None signals the
// command produced all its results (libpq returned a NULL PGresult).
// A non-OK result still comes back as Some — inspect it, then `pg_clear`
// every Some you receive.
@ pg_get_result Connection c → ?PgResult {
    : s raw ( PQgetResult . c raw )
    ? == # i raw 0 { ^ @ ?PgResult { F # PgResult 0 } } {}
    ^ @ ?PgResult { T @ PgResult { raw } }
}

// Block until the in-flight command finishes and return its final result.
// Intermediate results (only from multi-statement command strings) are
// cleared. CALLER `pg_clear`s the returned PgResult on the T arm.
@ pg_await Connection c → !PgResult PgErr {
    : ~ s last # s 0
    : ~ s cur ( PQgetResult . c raw )
    ~ != 0 # i cur {
        ? != 0 # i last { ( PQclear last ) } {}
        = last cur
        = cur ( PQgetResult . c raw )
    }
    ^ ( __pg_wrap_result last )
}

// ══════════════════════════════════════════════════════════════════
//  LISTEN / NOTIFY
// ══════════════════════════════════════════════════════════════════
//
// Issue `LISTEN chan` (via pg_run) on a connection, then have producers
// `NOTIFY chan, 'payload'`. To receive: when the connection's socket is
// readable, `pg_consume_input` then loop `pg_notifies` until None. Each
// PgNotify owns its `relname` / `extra` Strings — free with
// `pg_notify_free` (or read its fields then free).
: PgNotify { String relname  i be_pid  String extra }

// Pop the next buffered notification, or None if the queue is empty.
// Reads libpq's `PGnotify { char *relname; int be_pid; char *extra; }`
// (slots 0/1/2 of the i64-slot view; be_pid occupies the low 32 bits of
// slot 1) and copies the strings into owned Strings before freeing the
// libpq struct with PQfreemem.
@ pg_notifies Connection c → ?PgNotify {
    : s raw ( PQnotifies . c raw )
    ? == # i raw 0 { ^ @ ?PgNotify { F # PgNotify 0 } } {}
    : s rel # s ( nurl_peek raw 0 )
    : i pid & ( nurl_peek raw 1 ) 4294967295
    : s ext # s ( nurl_peek raw 2 )
    : String relname ? == # i rel 0 ( string_from `` ) ( string_from rel )
    : String extra ? == # i ext 0 ( string_from `` ) ( string_from ext )
    ( PQfreemem raw )
    ^ @ ?PgNotify { T @ PgNotify { relname pid extra } }
}

// Convenience: start listening on a channel. Auto-clears the result.
//
// SECURITY: a channel name is a SQL *identifier*, not a value, so it can
// NOT be bound with a `$1` placeholder — it must be quoted with
// PQescapeIdentifier (via pg_escape_identifier) before interpolation.
// Concatenating `channel` raw would be a SQL-injection hole
// (`pg_listen c "x; DROP TABLE users; --"`). `pg_notify_send` below has
// no such issue: it binds the channel as a *value* to `pg_notify($1,$2)`.
@ pg_listen Connection c s channel → !i PgErr {
    // pg_escape_identifier returns an OWNED, double-quote-wrapped String
    // (e.g. `"chan"`); free it after the exec. `nurl_str_cat`'s heap
    // result is auto-dropped at scope exit (libpq's PQexec has copied it
    // by the time pg_run returns — a manual nurl_free would double-free).
    : String esc ( pg_escape_identifier c channel )
    : s sql ( nurl_str_cat `LISTEN ` ( string_data esc ) )
    : !i PgErr r ( pg_run c sql )
    ( string_free esc )
    ^ r
}

// Convenience: send a notification with a text payload on a channel.
@ pg_notify_send Connection c s channel s payload → !i PgErr {
    : PgParams ps ( pg_params 2 )
    ( pg_bind_text ps channel )
    ( pg_bind_text ps payload )
    : !PgResult PgErr rr ( pg_exec_params_b c `SELECT pg_notify($1, $2)` ps )
    ^ ?? rr {
        T r → { ( pg_clear r )  @ !i PgErr { T 1 } }
        F e → @ !i PgErr { F # PgErr e }
    }
}

// Release a PgNotify's owned Strings.
@ pg_notify_free PgNotify n → v {
    ( string_free . n relname )
    ( string_free . n extra )
}

// ══════════════════════════════════════════════════════════════════
//  COPY — bulk row streaming
// ══════════════════════════════════════════════════════════════════
//
// COPY FROM STDIN (load):
//   ( pg_copy_start c `COPY t (a,b) FROM STDIN` )    // PGRES_COPY_IN (4)
//   ( pg_put_copy_str c ( string_from "1\tlo\n" ) )  // one row per call
//   ( pg_put_copy_end c )                      // finish the stream
//   ( pg_await c )                             // collect the COMMAND_OK
//
// COPY TO STDOUT (dump):
//   ( pg_copy_start c `COPY t TO STDOUT` )           // PGRES_COPY_OUT (3)
//   ~ … { ?? ( pg_get_copy_data c ) { T row → … F _ → break } }
//   ( pg_await c )                             // final COMMAND_OK

// Begin a COPY. Runs a `COPY … FROM STDIN` / `COPY … TO STDOUT` command
// and accepts its handshake status — PGRES_COPY_IN (4) or PGRES_COPY_OUT
// (3) — as success (plain pg_exec rejects these, since they are neither
// COMMAND_OK nor TUPLES_OK). The handshake result is cleared; the T arm
// carries the status so the caller can confirm the expected direction.
@ pg_copy_start Connection c s sql → !i PgErr {
    : s raw ( PQexec . c raw sql )
    ? == # i raw 0 { ^ @ !i PgErr { F # PgErr PgNullResult } } {}
    : PgResult r @ PgResult { raw }
    : i st ( pg_result_status r )
    ( pg_clear r )
    ? | == st 3 == st 4 { ^ @ !i PgErr { T st } } {}
    ^ @ !i PgErr { F # PgErr PgExecFailed }
}

// Feed `nbytes` of raw row data into a COPY FROM STDIN stream. 1 = ok,
// 0 = would block (non-blocking mode), -1 = error.
@ pg_put_copy_data Connection c s buf i nbytes → !i PgErr {
    : i32 nb # i32 nbytes
    : i rc # i ( PQputCopyData . c raw buf nb )
    ? < rc 0 { ^ @ !i PgErr { F # PgErr PgExecFailed } } {}
    ^ @ !i PgErr { T rc }
}

// Feed one text-format COPY row (caller includes the trailing newline).
@ pg_put_copy_str Connection c String row → !i PgErr {
    ^ ( pg_put_copy_data c ( string_data row ) ( string_len row ) )
}

// Close a COPY FROM STDIN stream successfully (NULL errormsg).
@ pg_put_copy_end Connection c → !i PgErr {
    : i rc # i ( PQputCopyEnd . c raw # s 0 )
    ? < rc 0 { ^ @ !i PgErr { F # PgErr PgExecFailed } } {}
    ^ @ !i PgErr { T rc }
}

// Pull the next COPY TO STDOUT row. None marks end-of-data (libpq -1 or
// -2). Each Some is an OWNED String holding one row's wire bytes (text
// COPY: the row text including its trailing newline). CALLER frees it.
@ pg_get_copy_data Connection c → ?String {
    : s slot ( nurl_alloc 8 )
    ( nurl_poke slot 0 0 )
    : **u bp # **u slot
    : i32 az # i32 0
    : i n # i ( PQgetCopyData . c raw bp az )
    ? <= n 0 {
        : s b0 # s ( nurl_peek slot 0 )
        ? != 0 # i b0 { ( PQfreemem b0 ) } {}
        ( nurl_free slot )
        ^ @ ?String { F # String 0 }
    } {}
    : s buf # s ( nurl_peek slot 0 )
    ( nurl_free slot )
    : String out ( string_from_bytes # *u buf n )
    ( PQfreemem buf )
    ^ @ ?String { T out }
}
