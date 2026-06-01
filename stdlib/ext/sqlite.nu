// stdlib/ext/sqlite.nu — SQLite bindings (Tier 3 stdlib).
//
// Declares libsqlite3 symbols directly via `& `sqlite3` @ … → …` and
// manages the small handle structs (Database + Statement) in opaque
// NURL-allocated 32-byte heap blocks. There is no `runtime.c` bridge;
// the compiler's FFI-lib-check scans every `&`-decl for the build-time
// sentinel `stdlib/runtime.sqlite3` — absent libsqlite3-dev → a clear
// compile-time diagnostic, not a cryptic linker error.
//
// API:
//
//   ( sqlite_open s path )                       → ! Database SqliteErr   READWRITE|CREATE
//   ( sqlite_open_v2 s path i flags )            → ! Database SqliteErr   explicit open flags
//   ( sqlite_close Database db )                 → v
//   ( sqlite_busy_timeout Database db i ms )     → ! v SqliteErr
//   ( sqlite_exec Database db s sql )            → ! i SqliteErr          i = rowcount
//   ( sqlite_errmsg Database db )                → String
//   ( sqlite_prepare Database db s sql )         → ! Statement SqliteErr
//   ( sqlite_bind_int Statement s i idx i val )       → ! v SqliteErr
//   ( sqlite_bind_text Statement s i idx String val ) → ! v SqliteErr     NUL-safe, explicit length
//   ( sqlite_bind_blob Statement s i idx ( Vec u ) data ) → ! v SqliteErr
//   ( sqlite_bind_null Statement s i idx )            → ! v SqliteErr
//   ( sqlite_step Statement s )                  → ! b SqliteErr          T = row, F = done
//   ( sqlite_column_count Statement s )          → i
//   ( sqlite_column_type Statement s i idx )     → i             1=int 2=float 3=text 4=blob 5=null
//   ( sqlite_column_int Statement s i idx )      → i
//   ( sqlite_column_text Statement s i idx )     → String        OWNED, NUL-safe (exact byte length)
//   ( sqlite_column_blob Statement s i idx )     → ( Vec u )      OWNED
//   ( sqlite_finalize Statement s )              → v
//   ( sqlite_reset Statement s )                 → ! v SqliteErr  reset cursor + clear bindings
//
// Handle layout (i64 slots, nurl_zalloc'd):
//
//   Database  { 0: sqlite3*       1: err_kind   2: errmsg (heap)    3: _ }
//   Statement { 0: sqlite3_stmt*  1: err_kind   2: text_buf (heap)  3: _ }
//
// Memory model — single-owner with auto-drop:
//
//   * `Database` and `Statement` implement `% Drop`. A scope-local
//     handle — including one unwrapped from a `! Database E` /
//     `! Statement E` result in a match arm — is closed AUTOMATICALLY
//     at scope exit, on EVERY path (Ok, Err, early return). You do NOT
//     need to call `sqlite_close` / `sqlite_finalize` manually for such
//     handles, and you MUST NOT also call them by hand — that is a
//     double free, exactly as it would be for any owned `Box` / `Vec`.
//   * `sqlite_close` / `sqlite_finalize` remain public for the
//     manually-managed case (e.g. a handle stored in a long-lived
//     struct field, which the auto-drop machinery does not track). They
//     are idempotent at the resource level: the OS handle is released
//     once and the slot zeroed, so a stale internal re-entry is a no-op.
//   * `sqlite_column_text` returns an OWNED String holding the column's
//     exact bytes (via sqlite3_column_bytes) — embedded NUL bytes are
//     preserved, no strlen truncation.
//   * `sqlite_column_blob` returns an OWNED `Vec u` of the exact bytes.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/cell.nu`

// ── libsqlite3 FFI ────────────────────────────────────────────────
//
// All `sqlite3 *` and `sqlite3_stmt *` pointers travel as `s` (opaque
// i64). Caller-owned out-pointer slots are 8-byte buffers we
// nurl_alloc immediately before the call and free immediately after.

& `sqlite3` @ sqlite3_open s filename *u out_db → i

& `sqlite3` @ sqlite3_open_v2 s filename *u out_db i flags s vfs → i

& `sqlite3` @ sqlite3_close s db → i

& `sqlite3` @ sqlite3_busy_timeout s db i ms → i

& `sqlite3` @ sqlite3_exec s db s sql *u cb *u data *u out_err → i

& `sqlite3` @ sqlite3_prepare_v2 s db s sql i n *u out_stmt *u tail → i

& `sqlite3` @ sqlite3_step s stmt → i

& `sqlite3` @ sqlite3_finalize s stmt → i

& `sqlite3` @ sqlite3_reset s stmt → i

& `sqlite3` @ sqlite3_clear_bindings s stmt → i

& `sqlite3` @ sqlite3_bind_int64 s stmt i idx i value → i

& `sqlite3` @ sqlite3_bind_text s stmt i idx s value i n *u destructor → i

& `sqlite3` @ sqlite3_bind_blob s stmt i idx s value i n *u destructor → i

& `sqlite3` @ sqlite3_bind_null s stmt i idx → i

& `sqlite3` @ sqlite3_column_int64 s stmt i idx → i

& `sqlite3` @ sqlite3_column_text s stmt i idx → s

& `sqlite3` @ sqlite3_column_blob s stmt i idx → s

& `sqlite3` @ sqlite3_column_bytes s stmt i idx → i

& `sqlite3` @ sqlite3_column_count s stmt → i

& `sqlite3` @ sqlite3_column_type s stmt i idx → i

& `sqlite3` @ sqlite3_changes s db → i

& `sqlite3` @ sqlite3_errmsg s db → s

& `sqlite3` @ sqlite3_free s p → v

// SQLITE_TRANSIENT — the documented constant value `((sqlite3_destructor_type)-1)`
// telling sqlite3_bind_text / _blob to copy the caller's bytes immediately.
// Encoded here as a numeric cast to *u so the FFI ABI passes
// (intptr_t)-1 to the destructor slot.
@ __sqlite_transient → *u {
    ^ # *u -1
}

// SQLite return codes we map on the result-enum side.
: i SQLITE_OK 0
: i SQLITE_ROW 100
: i SQLITE_DONE 101
// Sentinel for "build host has no libsqlite3" — never produced by
// libsqlite3 itself (it would have failed to link). Surfaced for API
// continuity with the previous C bridge.
: i NURL_SQLITE_UNSUPPORTED 99

// ── Open flags (sqlite3.h SQLITE_OPEN_*) ──────────────────────────
// Bit-or these for `sqlite_open_v2`. READONLY opens an existing DB for
// reads only (a write attempt errors instead of silently creating).
: i SQLITE_OPEN_READONLY 0x00000001
: i SQLITE_OPEN_READWRITE 0x00000002
: i SQLITE_OPEN_CREATE 0x00000004
: i SQLITE_OPEN_URI 0x00000040
: i SQLITE_OPEN_MEMORY 0x00000080
: i SQLITE_OPEN_NOMUTEX 0x00008000
: i SQLITE_OPEN_FULLMUTEX 0x00010000
: i SQLITE_OPEN_NOFOLLOW 0x01000000

: | SqliteErr {
    SqliteUnsupported  // build host lacked libsqlite3-dev
    SqliteOpen  // open failed (bad path, perm)
    SqliteSyntax  // SQL parse error (SQLITE_ERROR == 1)
    SqliteBusy  // SQLITE_BUSY == 5
    SqliteLocked  // SQLITE_LOCKED == 6
    SqliteReadOnly  // SQLITE_READONLY == 8 (write to a read-only DB)
    SqliteConstraint  // SQLITE_CONSTRAINT == 19
    SqliteMisuse  // SQLITE_MISUSE == 21
    SqliteIo  // SQLITE_IOERR == 10
    SqliteOther  // anything else, including unmapped codes
}

: Database { s raw }
: Statement { s raw }

@ sqlite_err_name SqliteErr e → s {
    ^ ?? e {
        SqliteUnsupported → `SqliteUnsupported`
        SqliteOpen → `SqliteOpen`
        SqliteSyntax → `SqliteSyntax`
        SqliteBusy → `SqliteBusy`
        SqliteLocked → `SqliteLocked`
        SqliteReadOnly → `SqliteReadOnly`
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
    ? == ek 8 { ^ # SqliteErr SqliteReadOnly } {}
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

// Tear down a Database heap handle, given the raw i8* slot pointer.
// Idempotent at the resource level: the sqlite3* slot is zeroed after
// sqlite3_close so a re-entry never double-closes the OS handle. Frees
// the 32-byte handle block exactly once — the caller must not reuse the
// pointer afterwards (single-owner contract, like any `*_free`).
@ __sqlite_db_destroy s h → v {
    ? == # i h 0 {} {
        : s db_ptr # s ( nurl_peek h 0 )
        ? != # i db_ptr 0 { ( sqlite3_close db_ptr ) ( nurl_poke h 0 0 ) } {}
        : s msg # s ( nurl_peek h 2 )
        ? != # i msg 0 { ( nurl_free msg ) ( nurl_poke h 2 0 ) } {}
        ( nurl_free h )
    }
}

// Tear down a Statement heap handle, given the raw i8* slot pointer.
@ __sqlite_stmt_destroy s h → v {
    ? == # i h 0 {} {
        : s stmt # s ( nurl_peek h 0 )
        ? != # i stmt 0 { ( sqlite3_finalize stmt ) ( nurl_poke h 0 0 ) } {}
        : s text_buf # s ( nurl_peek h 2 )
        ? != # i text_buf 0 { ( nurl_free text_buf ) ( nurl_poke h 2 0 ) } {}
        ( nurl_free h )
    }
}

// ── Database lifecycle ─────────────────────────────────────────────

// Open with explicit SQLITE_OPEN_* flags (bit-or them). Pass a NULL vfs
// (use the default). This is the production entry point — pick
// READONLY for untrusted / shared databases, add NOFOLLOW to refuse
// symlinked paths, etc.
@ sqlite_open_v2 s path i flags → !Database SqliteErr {
    : s h ( __db_alloc )
    : s out_buf ( nurl_zalloc 8 )
    : i rc ( sqlite3_open_v2 path # *u out_buf flags # s 0 )
    : s db # s ( nurl_peek out_buf 0 )
    ( nurl_free out_buf )
    ( nurl_poke h 0 # i db )
    ? != rc SQLITE_OK {
        ( nurl_poke h 1 rc )
        // Free the handle directly (no Database value, so no auto-drop
        // fires here) and surface the mapped error.
        ( __sqlite_db_destroy # s h )
        ^ @ !Database SqliteErr { F ( __sqlite_err_of rc ) }
    } {}
    : s rp # s h
    ^ @ !Database SqliteErr { T @ Database { rp } }
}

// Default open: read/write, create if missing — the historical
// `sqlite3_open` behaviour, now routed through open_v2.
@ sqlite_open s path → !Database SqliteErr {
    ^ ( sqlite_open_v2 path | SQLITE_OPEN_READWRITE SQLITE_OPEN_CREATE )
}

@ sqlite_close Database db → v {
    : s rp . db raw
    ( __sqlite_db_destroy # s rp )
}

// Set the busy handler timeout (milliseconds). A non-zero value makes
// SQLITE_BUSY block-and-retry for up to `ms` instead of failing
// immediately — essential under multi-process / multi-thread access.
@ sqlite_busy_timeout Database db i ms → !v SqliteErr {
    : s rp . db raw
    : i raw # i rp
    ? == raw 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteOther } } {}
    : s h # s raw
    : s db_ptr # s ( nurl_peek h 0 )
    ? == # i db_ptr 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_busy_timeout db_ptr ms )
    ( nurl_poke h 1 rc )
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
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
        // Free the statement handle directly (no Statement value here,
        // so auto-drop does not fire).
        ( __sqlite_stmt_destroy # s sh )
        ^ @ !Statement SqliteErr { F ( __sqlite_err_of rc ) }
    } {}
    : s srp # s sh
    ^ @ !Statement SqliteErr { T @ Statement { srp } }
}

@ sqlite_finalize Statement s → v {
    : s rp . s raw
    ( __sqlite_stmt_destroy # s rp )
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

// Bind text from a String — NUL-safe. The exact byte length is passed
// explicitly (sqlite3_bind_text with `n` rather than -1), so strings
// containing embedded NUL bytes round-trip intact. SQLITE_TRANSIENT
// makes libsqlite copy the bytes immediately, so `val` need not outlive
// this call.
@ sqlite_bind_text Statement s i idx String val → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i n ( string_len val )
    : s data ( string_data val )
    : i rc ( sqlite3_bind_text stmt idx data n ( __sqlite_transient ) )
    ( nurl_poke h 1 rc )
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// Bind a BLOB from a `Vec u`. The exact byte count is passed and the
// bytes are copied immediately (SQLITE_TRANSIENT). The only fully
// binary-safe write path.
@ sqlite_bind_blob Statement s i idx ( Vec u ) data → !v SqliteErr {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : i rc ( sqlite3_bind_blob stmt idx # s p n ( __sqlite_transient ) )
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

// Read a TEXT column as an OWNED String. Uses sqlite3_column_bytes for
// the exact UTF-8 length (call AFTER column_text, the order libsqlite
// documents) so embedded NUL bytes are preserved — no strlen
// truncation at the first NUL.
@ sqlite_column_text Statement s i idx → String {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ ( string_from `` ) } {}
    : s borrowed ( sqlite3_column_text stmt idx )
    ? == # i borrowed 0 { ^ ( string_from `` ) } {}
    : i n ( sqlite3_column_bytes stmt idx )
    ? <= n 0 { ^ ( string_from `` ) } {}
    ^ ( string_from_bytes # *u borrowed n )
}

// Read a BLOB column as an OWNED `Vec u`. Exact byte length via
// sqlite3_column_bytes; binary-safe.
@ sqlite_column_blob Statement s i idx → ( Vec u ) {
    : s rp . s raw
    : i raw # i rp
    : s h # s raw
    : s stmt # s ( nurl_peek h 0 )
    ? == # i stmt 0 { ^ ( vec_new [u] ) } {}
    : s borrowed ( sqlite3_column_blob stmt idx )
    ? == # i borrowed 0 { ^ ( vec_new [u] ) } {}
    : i n ( sqlite3_column_bytes stmt idx )
    ? <= n 0 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) out ( vec_with_cap [u] n )
    : *u dst ( vec_data [u] out )
    : *u src # *u borrowed
    ( nurl_memcpy dst src n )
    : b _ok ( vec_set_len [u] out n )
    ^ out
}

// ── Auto-drop (Drop trait) ────────────────────────────────────────
//
// A scope-local Database / Statement closes itself at scope exit on
// every path. See the "Memory model" note at the top: do not also call
// sqlite_close / sqlite_finalize by hand on an auto-dropped handle.

% Drop Database {
    @ drop Database db → v {
        ( sqlite_close db )
    }
}

% Drop Statement {
    @ drop Statement s → v {
        ( sqlite_finalize s )
    }
}
