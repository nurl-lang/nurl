// stdlib/ext/sqlite.nu — SQLite bindings (Tier 3 stdlib).
//
// Thin wrapper around the runtime's `nurl_sqlite_*` bridge
// (`stdlib/runtime.c §21`). Idiomatic NURL surface: every operation
// returns a typed `! T SqliteErr`, ownership rules documented below.
//
// API:
//
//   ( sqlite_open s path )                 → ! Database SqliteErr
//   ( sqlite_close Database db )           → v
//   ( sqlite_exec Database db s sql )      → ! i SqliteErr     i = rowcount
//   ( sqlite_prepare Database db s sql )   → ! Statement SqliteErr
//   ( sqlite_bind_int Statement s i idx i val ) → ! v SqliteErr
//   ( sqlite_bind_text Statement s i idx s val ) → ! v SqliteErr
//   ( sqlite_bind_null Statement s i idx )       → ! v SqliteErr
//   ( sqlite_step Statement s )                  → ! StepResult SqliteErr
//   ( sqlite_column_count Statement s )          → i
//   ( sqlite_column_type Statement s i idx )     → i             1=int 2=float 3=text 4=blob 5=null
//   ( sqlite_column_int Statement s i idx )      → i
//   ( sqlite_column_text Statement s i idx )     → String        OWNED
//   ( sqlite_finalize Statement s )              → v
//   ( sqlite_reset Statement s )                 → ! v SqliteErr  reset cursor + clear bindings
//
// Memory model:
//
//   * `sqlite_open` ALWAYS allocates a Database handle, even on Err —
//     the runtime keeps the handle around so the Err arm can carry
//     the diagnostic. On the Err arm `sqlite_close` must STILL be
//     called on the unwrapped handle inside the Err variant. The
//     module-level convention: extract via `?? r { T db → … F e →
//     ( sqlite_close . e db ) }` where SqliteErrInfo carries both.
//     OR call `sqlite_open_or_die` — out of scope for v1.
//   * `sqlite_prepare` returns an OWNED Statement; caller must call
//     `sqlite_finalize` even on the Err arm — same shape.
//   * `sqlite_column_text` returns an OWNED String (string_from of
//     the borrowed runtime slot). Free with `string_free`.
//   * `sqlite_exec` is the only path with NO statement lifecycle —
//     prepare + step + finalize happen inside libsqlite3.
//
// MVP scope NOT covered:
//   * BLOB columns / bindings (text only — callers stringify).
//   * Floating-point columns (use `column_text` + `string_to_float`).
//   * Multi-thread shared connections (each thread opens its own).
//   * Transactions via dedicated helpers — issue `BEGIN`/`COMMIT`
//     yourself with `sqlite_exec`.
//   * ATTACH, PRAGMA tuning, WAL mode setup — pure SQL recipes.
//
// Errors — `SqliteErr` mirrors the most-common SQLITE_* return codes:

$ `stdlib/core/string.nu`

: | SqliteErr {
    SqliteUnsupported   // build host lacked libsqlite3-dev
    SqliteOpen          // open failed (bad path, perm)
    SqliteSyntax        // SQL parse error (SQLITE_ERROR == 1)
    SqliteBusy          // SQLITE_BUSY == 5
    SqliteLocked        // SQLITE_LOCKED == 6
    SqliteConstraint    // SQLITE_CONSTRAINT == 19
    SqliteMisuse        // SQLITE_MISUSE == 21
    SqliteIo            // SQLITE_IOERR == 10
    SqliteOther         // anything else, including unmapped codes
}

: Database  { s raw }
: Statement { s raw }

// `sqlite_step` returns `!b SqliteErr` where the Ok bool means:
//   T  → SQLITE_ROW: another row is available; column_* are readable.
//   F  → SQLITE_DONE: end of result set; the caller should stop and
//        `sqlite_finalize` the statement.
// A tag-only enum would be more self-documenting but currently
// miscompiles when wrapped in `! T E`; bool is the pragmatic shape.

@ sqlite_err_name SqliteErr e → s {
    ^ ?? e {
        SqliteUnsupported → `SqliteUnsupported`
        SqliteOpen → `SqliteOpen`
        SqliteSyntax → `SqliteSyntax`
        SqliteBusy → `SqliteBusy`
        SqliteLocked → `SqliteLocked`
        SqliteConstraint → `SqliteConstraint`
        SqliteMisuse → `SqliteMisuse`
        SqliteIo → `SqliteIo`
        SqliteOther → `SqliteOther`
    }
}

// Map a raw runtime err_kind into the surface enum. The runtime
// passes SQLITE_* codes through unmodified for everything except OK
// (0) / ROW (100) / DONE (101) / UNSUPPORTED (99).
@ __sqlite_err_of i ek → SqliteErr {
    ? == ek 99 { ^ # SqliteErr SqliteUnsupported } {}
    ? == ek 1 { ^ # SqliteErr SqliteSyntax } {}
    ? == ek 5 { ^ # SqliteErr SqliteBusy } {}
    ? == ek 6 { ^ # SqliteErr SqliteLocked } {}
    ? == ek 10 { ^ # SqliteErr SqliteIo } {}
    ? == ek 19 { ^ # SqliteErr SqliteConstraint } {}
    ? == ek 21 { ^ # SqliteErr SqliteMisuse } {}
    ^ # SqliteErr SqliteOther
}

// ── Database lifecycle ─────────────────────────────────────────────

@ sqlite_open s path → !Database SqliteErr {
    : i raw ( nurl_sqlite_open path )
    ? == raw 0 { ^ @ !Database SqliteErr { F # SqliteErr SqliteOpen } } {}
    : i ek ( nurl_sqlite_err_kind raw )
    ? != ek 0 {
        ( nurl_sqlite_close raw )
        ^ @ !Database SqliteErr { F ( __sqlite_err_of ek ) }
    } {}
    : s rp # s raw
    ^ @ !Database SqliteErr { T @ Database { rp } }
}

@ sqlite_close Database db → v {
    : s rp . db raw
    : i raw # i rp
    ( nurl_sqlite_close raw )
}

// Read the runtime's borrowed error-message slot. Returned String is
// OWNED — caller frees with `string_free`. Empty on a healthy
// connection.
@ sqlite_errmsg Database db → String {
    : s rp . db raw
    : i raw # i rp
    : s msg ( nurl_sqlite_errmsg raw )
    ^ ( string_from msg )
}

// ── DDL / non-SELECT statements ───────────────────────────────────

@ sqlite_exec Database db s sql → !i SqliteErr {
    : s rp . db raw
    : i raw # i rp
    : i rc ( nurl_sqlite_exec raw sql )
    ? < rc 0 {
        : i ek ( nurl_sqlite_err_kind raw )
        ^ @ !i SqliteErr { F ( __sqlite_err_of ek ) }
    } {}
    ^ @ !i SqliteErr { T rc }
}

// ── Prepared statements ───────────────────────────────────────────

@ sqlite_prepare Database db s sql → !Statement SqliteErr {
    : s rp . db raw
    : i raw # i rp
    : i sraw ( nurl_sqlite_prepare raw sql )
    ? == sraw 0 { ^ @ !Statement SqliteErr { F # SqliteErr SqliteOther } } {}
    : i sek ( nurl_sqlite_stmt_err_kind sraw )
    ? != sek 0 {
        ( nurl_sqlite_finalize sraw )
        ^ @ !Statement SqliteErr { F ( __sqlite_err_of sek ) }
    } {}
    : s srp # s sraw
    ^ @ !Statement SqliteErr { T @ Statement { srp } }
}

@ sqlite_finalize Statement s → v {
    : s rp . s raw
    : i raw # i rp
    ( nurl_sqlite_finalize raw )
}

@ sqlite_reset Statement s → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : i ek ( nurl_sqlite_reset raw )
    ? != ek 0 { ^ @ !v SqliteErr { F ( __sqlite_err_of ek ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// ── Binding ───────────────────────────────────────────────────────

@ sqlite_bind_int Statement s i idx i val → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : i ek ( nurl_sqlite_bind_int raw idx val )
    ? != ek 0 { ^ @ !v SqliteErr { F ( __sqlite_err_of ek ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

@ sqlite_bind_text Statement s i idx s val → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : i ek ( nurl_sqlite_bind_text raw idx val )
    ? != ek 0 { ^ @ !v SqliteErr { F ( __sqlite_err_of ek ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

@ sqlite_bind_null Statement s i idx → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : i ek ( nurl_sqlite_bind_null raw idx )
    ? != ek 0 { ^ @ !v SqliteErr { F ( __sqlite_err_of ek ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// ── Stepping + column reads ──────────────────────────────────────

@ sqlite_step Statement s → !b SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : i rc ( nurl_sqlite_step raw )
    ? == rc 100 { ^ @ !b SqliteErr { T T } } {}
    ? == rc 101 { ^ @ !b SqliteErr { T F } } {}
    ^ @ !b SqliteErr { F ( __sqlite_err_of rc ) }
}

@ sqlite_column_count Statement s → i {
    : s rp . s raw
    : i raw # i rp
    ^ ( nurl_sqlite_column_count raw )
}

@ sqlite_column_type Statement s i idx → i {
    : s rp . s raw
    : i raw # i rp
    ^ ( nurl_sqlite_column_type raw idx )
}

@ sqlite_column_int Statement s i idx → i {
    : s rp . s raw
    : i raw # i rp
    ^ ( nurl_sqlite_column_int raw idx )
}

// Returns an OWNED String — runtime's borrowed view is snapshot via
// `string_from` because the underlying buffer is overwritten on the
// next column_text call or invalidated by step/finalize.
@ sqlite_column_text Statement s i idx → String {
    : s rp . s raw
    : i raw # i rp
    : s borrowed ( nurl_sqlite_column_text raw idx )
    ^ ( string_from borrowed )
}
