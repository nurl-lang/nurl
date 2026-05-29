// stdlib/ext/postgres.nu — PostgreSQL bindings via direct libpq FFI.
//
// **Pure-NURL FFI** — every libpq symbol is declared with `& `pq` @ ...`
// directly in this file. There is no `runtime.c` bridge, in contrast
// to `stdlib/ext/sqlite.nu` which routes through `nurl_sqlite_*`
// runtime wrappers. The compiler's FFI-lib-check (`gen_ffi_decl`)
// scans every `&`-decl for a build-time sentinel
// `stdlib/runtime.<libname>`; absent libpq-dev → clear compile-time
// diagnostic, not a cryptic linker error.
//
// API:
//
//   ( pg_connect s conninfo )                  → ! Connection PgErr
//   ( pg_close Connection c )                  → v
//   ( pg_err_msg Connection c )                → String          OWNED
//   ( pg_exec Connection c s sql )             → ! PgResult PgErr
//   ( pg_exec_params Connection c s sql ( Vec String ) params ) → ! PgResult PgErr
//   ( pg_result_status PgResult r )            → i               raw libpq ExecStatusType
//   ( pg_result_is_ok PgResult r )             → b
//   ( pg_ntuples PgResult r )                  → i
//   ( pg_nfields PgResult r )                  → i
//   ( pg_get_value PgResult r i row i col )    → String          OWNED
//   ( pg_get_is_null PgResult r i row i col )  → b
//   ( pg_field_name PgResult r i col )         → String          OWNED
//   ( pg_clear PgResult r )                    → v
//
// Memory model:
//
//   * `pg_connect` ALWAYS returns a Connection handle, even on Err —
//     libpq's `PQconnectdb` returns a non-NULL `PGconn*` even on
//     failure so the caller can inspect `PQerrorMessage`. On the Err
//     arm the handle MUST still be closed via `pg_close` to release
//     the underlying struct.
//   * `pg_exec` / `pg_exec_params` return an OWNED PgResult; the
//     caller MUST `pg_clear` it (`PQclear`) when done, even on Err.
//   * `pg_get_value` / `pg_field_name` / `pg_err_msg` return OWNED
//     Strings (copied via `string_from` because libpq's pointers
//     become invalid after `PQclear` / `PQfinish`).
//
// MVP scope NOT covered (intentional follow-ups):
//   * Binary protocol (`PQexecParams` always uses text-format here).
//   * COPY-FROM / COPY-TO streaming.
//   * Async / non-blocking mode (`PQsendQuery` + `PQconsumeInput`).
//   * LISTEN / NOTIFY notification channels.
//   * Prepared statements named on server (`PQprepare`, `PQexecPrepared`).
//   * SSL / GSSAPI auth tuning (connection string carries `sslmode=`).
//   * Large objects (lo_*).
//
// Errors — `PgErr` mirrors the most-common failure modes. libpq's
// fine-grained `ExecStatusType` codes ride the OK arm as the raw int
// (consulted via `pg_result_status` / `pg_result_is_ok`):

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | PgErr {
    PgConnectFailed  // PQstatus(conn) != CONNECTION_OK after PQconnectdb
    PgExecFailed  // PQresultStatus != PGRES_COMMAND_OK / PGRES_TUPLES_OK
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
// All NURL `s` parameters are i8* in LLVM, which is exactly the shape
// libpq expects for `const char *` arguments AND for returning
// `PGconn*` / `PGresult*` opaque handles. We thread those handles
// through NURL Connection / PgResult value structs as `s raw`.

& `pq` @ PQconnectdb s conninfo → s

& `pq` @ PQfinish s conn → v

& `pq` @ PQstatus s conn → i32

& `pq` @ PQerrorMessage s conn → s

& `pq` @ PQexec s conn s sql → s

& `pq` @ PQclear s res → v

& `pq` @ PQresultStatus s res → i32

& `pq` @ PQntuples s res → i32

& `pq` @ PQnfields s res → i32

& `pq` @ PQgetvalue s res i32 row i32 col → s

& `pq` @ PQgetisnull s res i32 row i32 col → i32

& `pq` @ PQfname s res i32 col → s
// Parameterised exec — text format only (paramTypes / paramLengths /
// paramFormats / resultFormat all set to 0/NULL so libpq treats every
// param as a NUL-terminated UTF-8 string and returns text rows).
& `pq` @ PQexecParams s conn s sql i32 n_params *u types **u values *i32 lens *i32 fmts i32 res_fmt → s

// PQstatus return codes (from libpq-fe.h):
//   CONNECTION_OK = 0
//   CONNECTION_BAD = 1
// PQresultStatus codes:
//   PGRES_COMMAND_OK = 1
//   PGRES_TUPLES_OK = 2
//   anything else → error (PGRES_BAD_RESPONSE = 5, PGRES_FATAL_ERROR = 7, …)

// ── Connection lifecycle ──────────────────────────────────────────

@ pg_connect s conninfo → !Connection PgErr {
    : s raw ( PQconnectdb conninfo )
    ? == 0 ( nurl_str_len raw ) {
        ^ @ !Connection PgErr { F # PgErr PgConnectFailed }
    } {}
    : i32 st ( PQstatus raw )
    : i sti # i st
    ? != sti 0 {
        // CONNECTION_BAD — caller must still close to release the struct.
        : Connection bad @ Connection { raw }
        ( pg_close bad )
        ^ @ !Connection PgErr { F # PgErr PgConnectFailed }
    } {}
    ^ @ !Connection PgErr { T @ Connection { raw } }
}

@ pg_close Connection c → v {
    ( PQfinish . c raw )
}

// Read the most recent error from the connection. Returned String is
// OWNED — caller frees with `string_free`. Empty on a healthy
// connection.
@ pg_err_msg Connection c → String {
    : s borrowed ( PQerrorMessage . c raw )
    ^ ( string_from borrowed )
}

// ── Statement execution ──────────────────────────────────────────

@ pg_exec Connection c s sql → !PgResult PgErr {
    : s raw ( PQexec . c raw sql )
    ? == 0 ( nurl_str_len raw ) {
        ^ @ !PgResult PgErr { F # PgErr PgNullResult }
    } {}
    : PgResult r @ PgResult { raw }
    ? ( pg_result_is_ok r ) {
        ^ @ !PgResult PgErr { T r }
    } {}
    ( pg_clear r )
    ^ @ !PgResult PgErr { F # PgErr PgExecFailed }
}

// Parameterised exec — every parameter is a NUL-terminated text-
// format string. NULL parameters are not supported in this MVP (use
// `IS NULL` in SQL with no bind). For binary parameters or NULLs,
// extend with `pg_exec_params_ex` later.
@ pg_exec_params Connection c s sql ( Vec String ) params → !PgResult PgErr {
    : i n ( vec_len [String] params )
    // Build a parallel array of `char *` pointers from the params Vec.
    // 8 bytes per pointer; libpq just reads, doesn't write.
    : s vals ( nurl_alloc * n 8 )
    : ~ i k 0
    ~ < k n {
        : ?String pk ( vec_get [String] params k )
        ?? pk {
            T sv → {
                : s sdata ( string_data sv )
                // nurl_poke uses SLOT indexing (×8 stride internally);
                // pass `k`, NOT `k * 8`.
                ( nurl_poke vals k # i sdata )
                ( string_free sv )
            }
            F _ → ( nurl_poke vals k 0 )
        }
        = k + k 1
    }
    : **u vptr # **u vals
    : *u types # *u 0
    : *i32 lens # *i32 0
    : *i32 fmts # *i32 0
    : i32 nn # i32 n
    : i32 zero # i32 0
    : s raw ( PQexecParams . c raw sql nn types vptr lens fmts zero )
    ( nurl_free vals )
    ? == 0 ( nurl_str_len raw ) {
        ^ @ !PgResult PgErr { F # PgErr PgNullResult }
    } {}
    : PgResult r @ PgResult { raw }
    ? ( pg_result_is_ok r ) {
        ^ @ !PgResult PgErr { T r }
    } {}
    ( pg_clear r )
    ^ @ !PgResult PgErr { F # PgErr PgExecFailed }
}

// ── Result inspection ────────────────────────────────────────────

@ pg_result_status PgResult r → i {
    : i32 st ( PQresultStatus . r raw )
    ^ # i st
}

@ pg_result_is_ok PgResult r → b {
    : i st ( pg_result_status r )
    ^ | == st 1 == st 2
}

@ pg_ntuples PgResult r → i {
    : i32 n ( PQntuples . r raw )
    ^ # i n
}

@ pg_nfields PgResult r → i {
    : i32 n ( PQnfields . r raw )
    ^ # i n
}

@ pg_get_value PgResult r i row i col → String {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    : s borrowed ( PQgetvalue . r raw r32 c32 )
    ^ ( string_from borrowed )
}

@ pg_get_is_null PgResult r i row i col → b {
    : i32 r32 # i32 row
    : i32 c32 # i32 col
    : i32 v ( PQgetisnull . r raw r32 c32 )
    ^ != 0 # i v
}

@ pg_field_name PgResult r i col → String {
    : i32 c32 # i32 col
    : s borrowed ( PQfname . r raw c32 )
    ^ ( string_from borrowed )
}

@ pg_clear PgResult r → v {
    ( PQclear . r raw )
}
