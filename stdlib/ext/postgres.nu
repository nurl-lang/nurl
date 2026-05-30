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
//     ( pg_get_int / pg_get_i64 … i col )  → i       text → integer
//     ( pg_get_f64 … )                     → f       text → double
//     ( pg_get_bool … )                    → b       't'/'f' → true/false
//     ( pg_clear PgResult )                → v
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

// PQstatus:        CONNECTION_OK = 0,  CONNECTION_BAD = 1
// PQresultStatus:  PGRES_COMMAND_OK = 1,  PGRES_TUPLES_OK = 2,
//                  PGRES_FATAL_ERROR = 7, …

// ── Connection lifecycle ──────────────────────────────────────────

// Open a connection. ALWAYS returns a handle (even on failure) so the
// caller can read `pg_err_msg`. Check `pg_ok`; always `pg_close`.
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
@ pg_get_bool PgResult r i row i col → b {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    : s v ( PQgetvalue . r raw r32 c32 )
    ^ == ( nurl_str_get v 0 ) 116
}

@ pg_clear PgResult r → v {
    ( PQclear . r raw )
}
