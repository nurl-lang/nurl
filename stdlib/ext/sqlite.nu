// stdlib/ext/sqlite.nu — SQLite bindings (Tier 3 stdlib).
//
// PURIFY.md Phase 12 §21 (2026-05-23): the entire 330-LOC C bridge
// in stdlib/runtime.c §21 migrated here. The module now declares
// libsqlite3 symbols directly via `& `sqlite3` @ … → …` (eighteen
// FFI lines) and manages the small handle structs (Database +
// Statement) in opaque NURL-allocated 32-byte heap blocks. The C
// side is a 5-LOC link-time stub.
//
// API (unchanged for callers — same Database / Statement / SqliteErr):
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
// Handle layout (i64 slots, nurl_zalloc'd):
//
//   Database  { 0: sqlite3*       1: err_kind   2: errmsg (heap)    3: _ }
//   Statement { 0: sqlite3_stmt*  1: err_kind   2: text_buf (heap)  3: _ }
//
// Memory model:
//
//   * `sqlite_open` ALWAYS allocates a Database handle, even on Err —
//     the runtime keeps the handle around so the Err arm can carry
//     the diagnostic. On the Err arm `sqlite_close` must STILL be
//     called on the unwrapped handle inside the Err variant.
//   * `sqlite_prepare` returns an OWNED Statement; caller must call
//     `sqlite_finalize` even on the Err arm.
//   * `sqlite_column_text` returns an OWNED String snapshotted from
//     the per-statement borrowed slot which lives until the next
//     step/finalize/column_text call.
//   * `sqlite_exec` is the only path with NO statement lifecycle.

$ `stdlib/core/string.nu`
$ `stdlib/core/cell.nu`

// ── libsqlite3 FFI ────────────────────────────────────────────────
//
// All `sqlite3 *` and `sqlite3_stmt *` pointers travel as `s` (opaque
// i64). Caller-owned out-pointer slots are 8-byte buffers we
// nurl_alloc immediately before the call and free immediately after.

& `sqlite3` @ sqlite3_open            s filename  *u out_db        → i
& `sqlite3` @ sqlite3_close           s db                          → i
& `sqlite3` @ sqlite3_exec            s db s sql *u cb *u data *u out_err → i
& `sqlite3` @ sqlite3_prepare_v2      s db s sql i n *u out_stmt *u tail  → i
& `sqlite3` @ sqlite3_step            s stmt                        → i
& `sqlite3` @ sqlite3_finalize        s stmt                        → i
& `sqlite3` @ sqlite3_reset           s stmt                        → i
& `sqlite3` @ sqlite3_clear_bindings  s stmt                        → i
& `sqlite3` @ sqlite3_bind_int64      s stmt i idx i value          → i
& `sqlite3` @ sqlite3_bind_text       s stmt i idx s value i n *u destructor → i
& `sqlite3` @ sqlite3_bind_null       s stmt i idx                  → i
& `sqlite3` @ sqlite3_column_int64    s stmt i idx                  → i
& `sqlite3` @ sqlite3_column_text     s stmt i idx                  → s
& `sqlite3` @ sqlite3_column_count    s stmt                        → i
& `sqlite3` @ sqlite3_column_type     s stmt i idx                  → i
& `sqlite3` @ sqlite3_changes         s db                          → i
& `sqlite3` @ sqlite3_errmsg          s db                          → s
& `sqlite3` @ sqlite3_free            s p                           → v

// SQLITE_TRANSIENT — the documented constant value `((sqlite3_destructor_type)-1)`
// telling sqlite3_bind_text to copy the caller's bytes immediately.
// Encoded here as a numeric cast to *u so the FFI ABI passes
// (intptr_t)-1 to the destructor slot.
@ __sqlite_transient → *u {
    ^ # *u -1
}

// SQLite return codes we map on the result-enum side.
: i SQLITE_OK         0
: i SQLITE_ROW        100
: i SQLITE_DONE       101
// Sentinel for "build host has no libsqlite3" — never produced by
// libsqlite3 itself (it would have failed to link). Surfaced for API
// continuity with the previous C bridge.
: i NURL_SQLITE_UNSUPPORTED 99

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

@ __sqlite_err_of i ek → SqliteErr {
    ? == ek NURL_SQLITE_UNSUPPORTED { ^ # SqliteErr SqliteUnsupported } {}
    ? == ek 1 { ^ # SqliteErr SqliteSyntax } {}
    ? == ek 5 { ^ # SqliteErr SqliteBusy } {}
    ? == ek 6 { ^ # SqliteErr SqliteLocked } {}
    ? == ek 10 { ^ # SqliteErr SqliteIo } {}
    ? == ek 19 { ^ # SqliteErr SqliteConstraint } {}
    ? == ek 21 { ^ # SqliteErr SqliteMisuse } {}
    ^ # SqliteErr SqliteOther
}

// ── Internal handle helpers ────────────────────────────────────────

@ __db_alloc → s { ^ ( nurl_zalloc 32 ) }
@ __stmt_alloc → s { ^ ( nurl_zalloc 32 ) }

@ __db_set_errmsg s h_db → v {
    : s db # s ( nurl_peek h_db 0 )
    : s old # s ( nurl_peek h_db 2 )
    ? != # i old 0 { ( nurl_free old ) ( nurl_poke h_db 2 0 ) } {}
    ? == # i db 0 {} {
        : s msg ( sqlite3_errmsg db )
        ? != # i msg 0 {
            : i n ( nurl_str_len msg )
            : s copy ( nurl_alloc + n 1 )
            : *u dst # *u copy
            : *u src # *u msg
            ( nurl_memcpy dst src n )
            = . dst n # u 0
            ( nurl_poke h_db 2 # i copy )
        } {}
    }
}

// ── Database lifecycle ─────────────────────────────────────────────

@ sqlite_open s path → !Database SqliteErr {
    : s h ( __db_alloc )
    : s out_buf ( nurl_zalloc 8 )
    : i rc ( sqlite3_open path # *u out_buf )
    : s db # s ( nurl_peek out_buf 0 )
    ( nurl_free out_buf )
    ( nurl_poke h 0 # i db )
    ? != rc SQLITE_OK {
        ( nurl_poke h 1 rc )
        ( __db_set_errmsg h )
        : s rp # s h
        : Database db_handle @ Database { rp }
        ( sqlite_close db_handle )
        ^ @ !Database SqliteErr { F ( __sqlite_err_of rc ) }
    } {}
    : s rp # s h
    ^ @ !Database SqliteErr { T @ Database { rp } }
}

@ sqlite_close Database db → v {
    : s rp . db raw
    : i raw # i rp
    ? == raw 0 {} {
        : s h # s raw
        : s db_ptr # s ( nurl_peek h 0 )
        ? != # i db_ptr 0 { ( sqlite3_close db_ptr ) } {}
        : s msg # s ( nurl_peek h 2 )
        ? != # i msg 0 { ( nurl_free msg ) } {}
        ( nurl_free h )
    }
}

@ sqlite_errmsg Database db → String {
    : s rp . db raw
    : i raw # i rp
    ? == raw 0 { ^ ( string_from `` ) } {}
    : s h # s raw
    : s msg # s ( nurl_peek h 2 )
    ? == # i msg 0 { ^ ( string_from `` ) } {}
    ^ ( string_from msg )
}

// ── DDL / non-SELECT statements ───────────────────────────────────

@ sqlite_exec Database db s sql → !i SqliteErr {
    : s rp . db raw
    : i raw # i rp
    ? == raw 0 { ^ @ !i SqliteErr { F # SqliteErr SqliteOther } } {}
    : s h # s raw
    : s db_ptr # s ( nurl_peek h 0 )
    ? == # i db_ptr 0 {
        ( nurl_poke h 1 NURL_SQLITE_UNSUPPORTED )
        ^ @ !i SqliteErr { F # SqliteErr SqliteUnsupported }
    } {}
    : s err_buf ( nurl_zalloc 8 )
    : i rc ( sqlite3_exec db_ptr sql # *u 0 # *u 0 # *u err_buf )
    : s err # s ( nurl_peek err_buf 0 )
    ( nurl_free err_buf )
    ? != rc SQLITE_OK {
        : s old # s ( nurl_peek h 2 )
        ? != # i old 0 { ( nurl_free old ) ( nurl_poke h 2 0 ) } {}
        ? != # i err 0 {
            : i n ( nurl_str_len err )
            : s copy ( nurl_alloc + n 1 )
            : *u dst # *u copy
            : *u src # *u err
            ( nurl_memcpy dst src n )
            = . dst n # u 0
            ( nurl_poke h 2 # i copy )
            ( sqlite3_free err )
        } { ( __db_set_errmsg h ) }
        ( nurl_poke h 1 rc )
        ^ @ !i SqliteErr { F ( __sqlite_err_of rc ) }
    } {}
    ( nurl_poke h 1 SQLITE_OK )
    ^ @ !i SqliteErr { T ( sqlite3_changes db_ptr ) }
}

// ── Prepared statements ───────────────────────────────────────────

@ sqlite_prepare Database db s sql → !Statement SqliteErr {
    : s rp . db raw
    : i raw # i rp
    ? == raw 0 { ^ @ !Statement SqliteErr { F # SqliteErr SqliteOther } } {}
    : s h # s raw
    : s db_ptr # s ( nurl_peek h 0 )
    ? == # i db_ptr 0 {
        ^ @ !Statement SqliteErr { F # SqliteErr SqliteUnsupported }
    } {}
    : s sh ( __stmt_alloc )
    : s out_buf ( nurl_zalloc 8 )
    : i rc ( sqlite3_prepare_v2 db_ptr sql -1 # *u out_buf # *u 0 )
    : s stmt # s ( nurl_peek out_buf 0 )
    ( nurl_free out_buf )
    ( nurl_poke sh 0 # i stmt )
    ? != rc SQLITE_OK {
        ( nurl_poke sh 1 rc )
        ( nurl_poke h 1 rc )
        ( __db_set_errmsg h )
        : s srp # s sh
        ( sqlite_finalize @ Statement { srp } )
        ^ @ !Statement SqliteErr { F ( __sqlite_err_of rc ) }
    } {}
    : s srp # s sh
    ^ @ !Statement SqliteErr { T @ Statement { srp } }
}

@ sqlite_finalize Statement s → v {
    : s rp . s raw
    : i raw # i rp
    ? == raw 0 {} {
        : s h # s raw
        : s stmt # s ( nurl_peek h 0 )
        ? != # i stmt 0 { ( sqlite3_finalize stmt ) } {}
        : s text_buf # s ( nurl_peek h 2 )
        ? != # i text_buf 0 { ( nurl_free text_buf ) } {}
        ( nurl_free h )
    }
}

@ sqlite_reset Statement s → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_reset stmt )
    ? == rc SQLITE_OK { ( sqlite3_clear_bindings stmt ) } {}
    ( nurl_poke h 1 rc )
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// ── Binding ───────────────────────────────────────────────────────

@ sqlite_bind_int Statement s i idx i val → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_bind_int64 stmt idx val )
    ( nurl_poke h 1 rc )
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

@ sqlite_bind_text Statement s i idx s val → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : s safe ? != # i val 0 val ``
    // SQLITE_TRANSIENT → libsqlite copies the bytes immediately, so we
    // don't need to keep `val` alive past this call.
    : i rc ( sqlite3_bind_text stmt idx safe -1 ( __sqlite_transient ) )
    ( nurl_poke h 1 rc )
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

@ sqlite_bind_null Statement s i idx → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_bind_null stmt idx )
    ( nurl_poke h 1 rc )
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// ── Stepping + column reads ──────────────────────────────────────

@ sqlite_step Statement s → !b SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ @ !b SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_step stmt )
    ? == rc SQLITE_ROW {
        ( nurl_poke h 1 SQLITE_OK )
        ^ @ !b SqliteErr { T T }
    } {}
    ? == rc SQLITE_DONE {
        ( nurl_poke h 1 SQLITE_OK )
        ^ @ !b SqliteErr { T F }
    } {}
    ( nurl_poke h 1 rc )
    ^ @ !b SqliteErr { F ( __sqlite_err_of rc ) }
}

@ sqlite_column_count Statement s → i {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ 0 } {}
    ^ ( sqlite3_column_count stmt )
}

@ sqlite_column_type Statement s i idx → i {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ 5 } {}
    ^ ( sqlite3_column_type stmt idx )
}

@ sqlite_column_int Statement s i idx → i {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ 0 } {}
    ^ ( sqlite3_column_int64 stmt idx )
}

@ sqlite_column_text Statement s i idx → String {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ ( string_from `` ) } {}
    : s borrowed ( sqlite3_column_text stmt idx )
    : s safe ? != # i borrowed 0 borrowed ``
    // Snapshot into the handle's text_buf slot — same lifetime contract
    // the C bridge exposed (stable until next column_text / step /
    // finalize). The NURL caller hot-copies via string_from anyway, so
    // this is mostly a courtesy + a sanity net for re-reads.
    : s old # s ( nurl_peek h 2 )
    ? != # i old 0 { ( nurl_free old ) ( nurl_poke h 2 0 ) } {}
    : i n ( nurl_str_len safe )
    : s copy ( nurl_alloc + n 1 )
    : *u dst # *u copy
    : *u src # *u safe
    ( nurl_memcpy dst src n )
    = . dst n # u 0
    ( nurl_poke h 2 # i copy )
    ^ ( string_from copy )
}
