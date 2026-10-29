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
//   ( sqlite_bind_double Statement s i idx f val )    → ! v SqliteErr
//   ( sqlite_bind_blob Statement s i idx ( Vec u ) data ) → ! v SqliteErr
//   ( sqlite_bind_null Statement s i idx )            → ! v SqliteErr
//   ( sqlite_step Statement s )                  → ! b SqliteErr          T = row, F = done
//   ( sqlite_column_count Statement s )          → i
//   ( sqlite_column_type Statement s i idx )     → i             1=int 2=float 3=text 4=blob 5=null
//   ( sqlite_column_int Statement s i idx )      → i
//   ( sqlite_column_double Statement s i idx )   → f
//   ( sqlite_column_text Statement s i idx )     → String        OWNED, NUL-safe (exact byte length)
//   ( sqlite_column_blob Statement s i idx )     → ( Vec u )      OWNED
//   ( sqlite_column_is_null Statement s i idx )  → b
//   ( sqlite_finalize Statement s )              → v
//   ( sqlite_reset Statement s )                 → ! v SqliteErr  reset cursor + clear bindings
//
//   Transactions:
//   ( sqlite_begin / commit / rollback Database db )  → ! i SqliteErr
//   ( with_transaction Database db ( @ !v SqliteErr Database ) body ) → ! v SqliteErr
//                                                COMMIT on Ok, ROLLBACK on Err
//
//   Introspection / hardening (untrusted SQL/DB):
//   ( sqlite_last_insert_rowid Database db )     → i
//   ( sqlite_set_defensive Database db b on )    → ! v SqliteErr
//   ( sqlite_enable_load_extension Database db b on ) → ! v SqliteErr
//   ( sqlite_harden Database db )                → ! v SqliteErr  DEFENSIVE on + load_ext off
//   ( sqlite_limit Database db i id i newVal )   → i              prior value
//   ( sqlite_set_authorizer Database db ( @ i i s s s s ) auth ) → ! v SqliteErr
//   ( sqlite_clear_authorizer Database db )      → ! v SqliteErr
//
//   PRAGMA helpers:
//   ( sqlite_journal_wal Database db )           → ! i SqliteErr
//   ( sqlite_foreign_keys Database db b on )     → ! i SqliteErr
//   ( sqlite_synchronous Database db s mode )    → ! i SqliteErr  "OFF"/"NORMAL"/"FULL"/"EXTRA"
//
// Handle state (a Box each, released with the handle):
//
//   Database  → DbState   { sqlite3*, err_kind, errmsg, the authorizer }
//   Statement → StmtState { sqlite3_stmt*, err_kind }
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
$ `stdlib/core/marker.nu`
$ `stdlib/core/box.nu`

// ── libsqlite3 FFI ────────────────────────────────────────────────
//
// `sqlite3 *` and `sqlite3_stmt *` travel as `*u`. The out-pointers
// sqlite3_open* / sqlite3_prepare_v2 write are `inout` locals.

& `sqlite3` @ sqlite3_open s filename inout *u out_db → i

& `sqlite3` @ sqlite3_open_v2 s filename inout *u out_db i flags s vfs → i

& `sqlite3` @ sqlite3_close *u db → i

& `sqlite3` @ sqlite3_close_v2 *u db → i

& `sqlite3` @ sqlite3_busy_timeout *u db i ms → i

& `sqlite3` @ sqlite3_exec *u db s sql *u cb *u data *u out_err → i

& `sqlite3` @ sqlite3_prepare_v2 *u db s sql i n inout *u out_stmt *u tail → i

& `sqlite3` @ sqlite3_step *u stmt → i

& `sqlite3` @ sqlite3_finalize *u stmt → i

& `sqlite3` @ sqlite3_reset *u stmt → i

& `sqlite3` @ sqlite3_clear_bindings *u stmt → i

& `sqlite3` @ sqlite3_bind_int64 *u stmt i idx i value → i

& `sqlite3` @ sqlite3_bind_text *u stmt i idx in *u value i n in *u destructor → i

& `sqlite3` @ sqlite3_bind_blob *u stmt i idx in *u value i n in *u destructor → i

& `sqlite3` @ sqlite3_bind_null *u stmt i idx → i

& `sqlite3` @ sqlite3_bind_double *u stmt i idx f value → i

& `sqlite3` @ sqlite3_column_double *u stmt i idx → f

& `sqlite3` @ sqlite3_column_int64 *u stmt i idx → i

& `sqlite3` @ sqlite3_column_text *u stmt i idx → s

& `sqlite3` @ sqlite3_column_blob *u stmt i idx → *u

& `sqlite3` @ sqlite3_column_bytes *u stmt i idx → i

& `sqlite3` @ sqlite3_column_count *u stmt → i

& `sqlite3` @ sqlite3_column_type *u stmt i idx → i

& `sqlite3` @ sqlite3_changes *u db → i

& `sqlite3` @ sqlite3_errmsg *u db → s

& `sqlite3` @ sqlite3_free *u p → v

& `sqlite3` @ sqlite3_last_insert_rowid *u db → i

& `sqlite3` @ sqlite3_extended_result_codes *u db i onoff → i

& `sqlite3` @ sqlite3_extended_errcode *u db → i

& `sqlite3` @ sqlite3_limit *u db i id i newVal → i

& `sqlite3` @ sqlite3_set_authorizer *u db *u xAuth *u pUserData → i

// sqlite3_db_config(sqlite3*, int op, ...) is variadic in C. For the
// (int onoff, int *pRes) verbs we use (DEFENSIVE / ENABLE_LOAD_EXTENSION)
// the `...` marker makes nurlc emit the correct variadic-call ABI.
& `sqlite3` @ sqlite3_db_config *u db i op ... → i

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

// ── db_config verbs (sqlite3.h SQLITE_DBCONFIG_*) ─────────────────
: i SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION 1005
: i SQLITE_DBCONFIG_DEFENSIVE 1010

// ── limit categories (sqlite3.h SQLITE_LIMIT_*) ───────────────────
: i SQLITE_LIMIT_LENGTH 0
: i SQLITE_LIMIT_SQL_LENGTH 1
: i SQLITE_LIMIT_COLUMN 2
: i SQLITE_LIMIT_EXPR_DEPTH 3
: i SQLITE_LIMIT_COMPOUND_SELECT 4
: i SQLITE_LIMIT_VDBE_OP 5
: i SQLITE_LIMIT_FUNCTION_ARG 6
: i SQLITE_LIMIT_ATTACHED 7
: i SQLITE_LIMIT_LIKE_PATTERN_LENGTH 8
: i SQLITE_LIMIT_VARIABLE_NUMBER 9
: i SQLITE_LIMIT_TRIGGER_DEPTH 10

// ── authorizer return codes (xAuth must return one of these) ──────
// SQLITE_OK (0) = allow. The two below are the only other legal returns.
: i SQLITE_DENY 1  // abort the SQL statement with an error
: i SQLITE_IGNORE 2  // disallow the action but don't error (NULL/skip)

// ── authorizer action codes (2nd arg to xAuth) — common subset ────
: i SQLITE_CREATE_INDEX 1
: i SQLITE_CREATE_TABLE 2
: i SQLITE_CREATE_TEMP_TABLE 4
: i SQLITE_CREATE_TRIGGER 7
: i SQLITE_DELETE 9
: i SQLITE_DROP_INDEX 10
: i SQLITE_DROP_TABLE 11
: i SQLITE_DROP_TRIGGER 14
: i SQLITE_INSERT 18
: i SQLITE_PRAGMA 19
: i SQLITE_READ 20
: i SQLITE_SELECT 21
: i SQLITE_TRANSACTION 22
: i SQLITE_UPDATE 23
: i SQLITE_ATTACH 24
: i SQLITE_DETACH 25
: i SQLITE_FUNCTION 31

: | SqliteErr {
    SqliteUnsupported  // build host lacked libsqlite3-dev
    SqliteOpen  // open failed (bad path, perm)
    SqliteSyntax  // SQL parse error (SQLITE_ERROR == 1)
    SqliteBusy  // SQLITE_BUSY == 5
    SqliteLocked  // SQLITE_LOCKED == 6
    SqliteReadOnly  // SQLITE_READONLY == 8 (write to a read-only DB)
    SqliteConstraint  // SQLITE_CONSTRAINT == 19 (unmapped extended sub-code)
    // Extended constraint sub-codes (surfaced once extended result
    // codes are enabled — they are, automatically, on every open).
    SqliteConstraintUnique  // SQLITE_CONSTRAINT_UNIQUE     == 2067
    SqliteConstraintForeignKey  // SQLITE_CONSTRAINT_FOREIGNKEY == 787
    SqliteConstraintNotNull  // SQLITE_CONSTRAINT_NOTNULL    == 1299
    SqliteConstraintPrimaryKey  // SQLITE_CONSTRAINT_PRIMARYKEY == 1555
    SqliteConstraintCheck  // SQLITE_CONSTRAINT_CHECK      == 275
    SqliteMisuse  // SQLITE_MISUSE == 21
    SqliteIo  // SQLITE_IOERR == 10
    SqliteOther  // anything else, including unmapped codes
}

// A connection's state: the sqlite3*, the last result code, a copy of the
// last error message, and the authorizer libsqlite calls (the handle's own
// copy, so its env outlives every call).
: DbState { * u db i rc String errmsg ? ( @ i i s s s s ) auth }

: StmtState { * u stmt i rc }

: Database { ( Box DbState ) st }

// Its drop closes something the outside world sees (stdlib/core/marker.nu).
% Resource Database {}

: Statement { ( Box StmtState ) st }

// Its drop closes something the outside world sees (stdlib/core/marker.nu).
% Resource Statement {}

@ sqlite_err_name SqliteErr e → s {
    ^ ?? e {
        SqliteUnsupported → `SqliteUnsupported`
        SqliteOpen → `SqliteOpen`
        SqliteSyntax → `SqliteSyntax`
        SqliteBusy → `SqliteBusy`
        SqliteLocked → `SqliteLocked`
        SqliteReadOnly → `SqliteReadOnly`
        SqliteConstraint → `SqliteConstraint`
        SqliteConstraintUnique → `SqliteConstraintUnique`
        SqliteConstraintForeignKey → `SqliteConstraintForeignKey`
        SqliteConstraintNotNull → `SqliteConstraintNotNull`
        SqliteConstraintPrimaryKey → `SqliteConstraintPrimaryKey`
        SqliteConstraintCheck → `SqliteConstraintCheck`
        SqliteMisuse → `SqliteMisuse`
        SqliteIo → `SqliteIo`
        SqliteOther → `SqliteOther`
    }
}

@ __sqlite_err_of i ek → SqliteErr {
    ? == ek NURL_SQLITE_UNSUPPORTED { ^ # SqliteErr SqliteUnsupported } {}
    // Extended constraint sub-codes first (specific → general). These
    // are what `sqlite3_extended_result_codes(db, 1)` surfaces so the
    // caller can tell a UNIQUE violation from a FOREIGN KEY one.
    ? == ek 2067 { ^ # SqliteErr SqliteConstraintUnique } {}
    ? == ek 787 { ^ # SqliteErr SqliteConstraintForeignKey } {}
    ? == ek 1299 { ^ # SqliteErr SqliteConstraintNotNull } {}
    ? == ek 1555 { ^ # SqliteErr SqliteConstraintPrimaryKey } {}
    ? == ek 275 { ^ # SqliteErr SqliteConstraintCheck } {}
    // Primary code fallback: the low byte of any (extended or not) code
    // is the historical primary result code.
    : i prim & ek 0xFF
    ? == prim 1 { ^ # SqliteErr SqliteSyntax } {}
    ? == prim 5 { ^ # SqliteErr SqliteBusy } {}
    ? == prim 6 { ^ # SqliteErr SqliteLocked } {}
    ? == prim 8 { ^ # SqliteErr SqliteReadOnly } {}
    ? == prim 10 { ^ # SqliteErr SqliteIo } {}
    ? == prim 19 { ^ # SqliteErr SqliteConstraint } {}
    ? == prim 21 { ^ # SqliteErr SqliteMisuse } {}
    ^ # SqliteErr SqliteOther
}

// ── Internal handle helpers ────────────────────────────────────────

// The state in place (null for a handle that holds none).
@ __db_state Database d → *DbState { ^ ( box_ptr [DbState] . d st ) }

@ __stmt_state Statement t → *StmtState { ^ ( box_ptr [StmtState] . t st ) }

// Keep a copy of the connection's current error message.
@ __db_set_errmsg * DbState h → v {
    ? == # i . h db 0 { = . h errmsg ( string_new ) ^ } {}
    : s msg ( sqlite3_errmsg . h db )
    = . h errmsg ? == # i msg 0 ( string_new ) ( string_from msg )
}

// ── Database lifecycle ─────────────────────────────────────────────

// Open with explicit SQLITE_OPEN_* flags (bit-or them). Pass a NULL vfs
// (use the default). This is the production entry point — pick
// READONLY for untrusted / shared databases, add NOFOLLOW to refuse
// symlinked paths, etc.
@ sqlite_open_v2 s path i flags → !Database SqliteErr {
    : ~ * u out # *u 0
    : i rc ( sqlite3_open_v2 path out flags # s 0 )
    // A failed open may still hand back a connection: the handle closes
    // it when it goes, on the error path too.
    : Database d @ Database { ( box_new [DbState] @ DbState { out rc ( string_new ) @ ?( @ i i s s s s ) { F } } ) }
    ? != rc SQLITE_OK { ^ @ !Database SqliteErr { F ( __sqlite_err_of rc ) } } {}
    // Surface extended result codes (e.g. CONSTRAINT_UNIQUE vs
    // CONSTRAINT_FOREIGNKEY) on every error from this connection.
    ( sqlite3_extended_result_codes out 1 )
    ^ @ !Database SqliteErr { T d }
}

// Default open: read/write, create if missing — the historical
// `sqlite3_open` behaviour, now routed through open_v2.
@ sqlite_open s path → !Database SqliteErr {
    ^ ( sqlite_open_v2 path | SQLITE_OPEN_READWRITE SQLITE_OPEN_CREATE )
}

// Close the connection now (optional: the handle does it when it goes).
// Idempotent: the sqlite3* is cleared after the close.
//
// A Statement of this connection may still be alive (its own handle,
// finalized when it goes): sqlite3_close would refuse (SQLITE_BUSY) and
// leave the connection open with nobody to close it, so the close is
// sqlite3_close_v2's — the connection is released now, or, while a
// statement lives, when the last one is finalized. Such a statement may
// still re-prepare (a schema change), which runs the authorizer: it is
// uninstalled first, so the handle's copy of it can go now.
@ sqlite_close Database db → v {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ } {}
    ? != # i . h db 0 {
        ?? . h auth { T _a → { : i _ra ( sqlite3_set_authorizer . h db # *u 0 # *u 0 ) } F → {} }
        : i _rc ( sqlite3_close_v2 . h db )
        = . h db # *u 0
    } {}
    = . h auth @ ?( @ i i s s s s ) { F }
}

// Set the busy handler timeout (milliseconds). A non-zero value makes
// SQLITE_BUSY block-and-retry for up to `ms` instead of failing
// immediately — essential under multi-process / multi-thread access.
@ sqlite_busy_timeout Database db i ms → !v SqliteErr {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteOther } } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_busy_timeout db_ptr ms )
    = . h rc rc
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

@ sqlite_errmsg Database db → String {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ ( string_new ) } {}
    ^ ( string_clone . h errmsg )
}

// ── DDL / non-SELECT statements ───────────────────────────────────

@ sqlite_exec Database db s sql → !i SqliteErr {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ @ !i SqliteErr { F # SqliteErr SqliteOther } } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 {
        = . h rc NURL_SQLITE_UNSUPPORTED
        ^ @ !i SqliteErr { F # SqliteErr SqliteUnsupported }
    } {}
    // No out-message: on failure the connection's own message (what
    // sqlite3_exec would have copied out) is read with sqlite3_errmsg,
    // so there is no sqlite-allocated string to give back.
    : i rc ( sqlite3_exec db_ptr sql # *u 0 # *u 0 # *u 0 )
    ? != rc SQLITE_OK {
        ( __db_set_errmsg h )
        = . h rc rc
        ^ @ !i SqliteErr { F ( __sqlite_err_of rc ) }
    } {}
    = . h rc SQLITE_OK
    ^ @ !i SqliteErr { T ( sqlite3_changes db_ptr ) }
}

// ── Prepared statements ───────────────────────────────────────────

@ sqlite_prepare Database db s sql → !Statement SqliteErr {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ @ !Statement SqliteErr { F # SqliteErr SqliteOther } } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 {
        ^ @ !Statement SqliteErr { F # SqliteErr SqliteUnsupported }
    } {}
    : ~ * u out # *u 0
    : i rc ( sqlite3_prepare_v2 db_ptr sql -1 out # *u 0 )
    // A failed prepare may still hand back a statement: the handle
    // finalizes it when it goes.
    : Statement t @ Statement { ( box_new [StmtState] @ StmtState { out rc } ) }
    ? != rc SQLITE_OK {
        = . h rc rc
        ( __db_set_errmsg h )
        ^ @ !Statement SqliteErr { F ( __sqlite_err_of rc ) }
    } {}
    ^ @ !Statement SqliteErr { T t }
}

// Finalize the statement now (optional: the handle does it when it goes).
@ sqlite_finalize Statement s → v {
    : *StmtState h ( __stmt_state s )
    ? == # i h 0 { ^ } {}
    ? != # i . h stmt 0 { : i _rc ( sqlite3_finalize . h stmt ) = . h stmt # *u 0 } {}
}

@ sqlite_reset Statement s → !v SqliteErr {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_reset stmt )
    ? == rc SQLITE_OK { ( sqlite3_clear_bindings stmt ) } {}
    = . h rc rc
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// ── Binding ───────────────────────────────────────────────────────

@ sqlite_bind_int Statement s i idx i val → !v SqliteErr {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_bind_int64 stmt idx val )
    = . h rc rc
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// Bind text from a String — NUL-safe. The exact byte length is passed
// explicitly (sqlite3_bind_text with `n` rather than -1), so strings
// containing embedded NUL bytes round-trip intact. SQLITE_TRANSIENT
// makes libsqlite copy the bytes immediately, so `val` need not outlive
// this call.
@ sqlite_bind_text Statement s i idx String val → !v SqliteErr {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i n ( string_len val )
    : s data ( string_data val )
    : i rc ( sqlite3_bind_text stmt idx data n ( __sqlite_transient ) )
    = . h rc rc
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// Bind an f64 (REAL) parameter.
@ sqlite_bind_double Statement s i idx f val → !v SqliteErr {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_bind_double stmt idx val )
    = . h rc rc
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// Bind a BLOB from a `Vec u`. The exact byte count is passed and the
// bytes are copied immediately (SQLITE_TRANSIENT). The only fully
// binary-safe write path.
@ sqlite_bind_blob Statement s i idx ( Vec u ) data → !v SqliteErr {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : i rc ( sqlite3_bind_blob stmt idx # s p n ( __sqlite_transient ) )
    = . h rc rc
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

@ sqlite_bind_null Statement s i idx → !v SqliteErr {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_bind_null stmt idx )
    = . h rc rc
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// ── Stepping + column reads ──────────────────────────────────────

@ sqlite_step Statement s → !b SqliteErr {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ @ !b SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_step stmt )
    ? == rc SQLITE_ROW {
        = . h rc SQLITE_OK
        ^ @ !b SqliteErr { T T }
    } {}
    ? == rc SQLITE_DONE {
        = . h rc SQLITE_OK
        ^ @ !b SqliteErr { T F }
    } {}
    = . h rc rc
    ^ @ !b SqliteErr { F ( __sqlite_err_of rc ) }
}

@ sqlite_column_count Statement s → i {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ 0 } {}
    ^ ( sqlite3_column_count stmt )
}

@ sqlite_column_type Statement s i idx → i {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ 5 } {}
    ^ ( sqlite3_column_type stmt idx )
}

@ sqlite_column_int Statement s i idx → i {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ 0 } {}
    ^ ( sqlite3_column_int64 stmt idx )
}

// Read a TEXT column as an OWNED String. Uses sqlite3_column_bytes for
// the exact UTF-8 length (call AFTER column_text, the order libsqlite
// documents) so embedded NUL bytes are preserved — no strlen
// truncation at the first NUL.
@ sqlite_column_text Statement s i idx → String {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
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
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
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

// Read an f64 (REAL) column. Returns 0.0 on a closed statement.
@ sqlite_column_double Statement s i idx → f {
    : *StmtState h ( __stmt_state s )
    : *u stmt . h stmt
    ? == # i stmt 0 { ^ # f 0 } {}
    ^ ( sqlite3_column_double stmt idx )
}

// NULL check for a column (column_type == SQLITE_NULL == 5).
@ sqlite_column_is_null Statement s i idx → b {
    ^ == ( sqlite_column_type s idx ) 5
}

// ── Transactions (§9) ─────────────────────────────────────────────

@ sqlite_begin Database db → !i SqliteErr {
    ^ ( sqlite_exec db `BEGIN` )
}

@ sqlite_commit Database db → !i SqliteErr {
    ^ ( sqlite_exec db `COMMIT` )
}

@ sqlite_rollback Database db → !i SqliteErr {
    ^ ( sqlite_exec db `ROLLBACK` )
}

// Run `body` inside a transaction: BEGIN, then call the closure; COMMIT
// on Ok, ROLLBACK on Err (propagating the original error). The closure
// receives the (borrowed) Database so it can prepare/exec inside the
// transaction. `db` is NOT closed here — it is a borrow.
@ with_transaction Database db ( @ !v SqliteErr Database ) body → !v SqliteErr {
    : !i SqliteErr bg ( sqlite_begin db )
    ?? bg {
        F e → { ^ @ !v SqliteErr { F e } }
        T _ → {}
    }
    : !v SqliteErr r ( body db )
    ?? r {
        F e → {
            : !i SqliteErr _rb ( sqlite_rollback db )
            ^ @ !v SqliteErr { F e }
        }
        T _ → {
            : !i SqliteErr cm ( sqlite_commit db )
            ?? cm {
                F e2 → { ^ @ !v SqliteErr { F e2 } }
                T _ → { ^ @ !v SqliteErr { T 0 } }
            }
        }
    }
}

// ── Introspection (§12) ───────────────────────────────────────────

@ sqlite_last_insert_rowid Database db → i {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ 0 } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 { ^ 0 } {}
    ^ ( sqlite3_last_insert_rowid db_ptr )
}

// Rows changed by the most recent INSERT/UPDATE/DELETE on this
// connection. `sqlite_exec` already returns this for one-shot SQL; this
// is the equivalent for statements run through prepare/step (where the
// count was previously unreachable).
@ sqlite_changes Database db → i {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ 0 } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 { ^ 0 } {}
    ^ ( sqlite3_changes db_ptr )
}

// ── Hardening for untrusted SQL / DB (§13 / §14) ──────────────────

// SQLITE_DBCONFIG_DEFENSIVE: refuse SQL that can corrupt the DB (writes
// to shadow tables, schema poking). Recommended for untrusted SQL.
@ sqlite_set_defensive Database db b on → !v SqliteErr {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteOther } } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_db_config db_ptr SQLITE_DBCONFIG_DEFENSIVE ? on 1 0 # *u 0 )
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION: gate the load_extension() SQL
// function + C API. Disable it (on = F) to block extension-loading RCE
// from a hostile DB / SQL string.
@ sqlite_enable_load_extension Database db b on → !v SqliteErr {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteOther } } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_db_config db_ptr SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION ? on 1 0 # *u 0 )
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    ^ @ !v SqliteErr { T 0 }
}

// One-call hardening for opening an untrusted database: turn DEFENSIVE
// on and extension-loading off.
@ sqlite_harden Database db → !v SqliteErr {
    : !v SqliteErr d ( sqlite_set_defensive db T )
    ?? d { F e → { ^ @ !v SqliteErr { F e } } T _ → {} }
    ^ ( sqlite_enable_load_extension db F )
}

// Lower a complexity limit (e.g. SQLITE_LIMIT_SQL_LENGTH,
// _LIKE_PATTERN_LENGTH, _EXPR_DEPTH, _VDBE_OP) to bound the cost of
// untrusted SQL. Returns the PRIOR value of the limit (sqlite3_limit
// semantics); a negative `newVal` queries without changing.
@ sqlite_limit Database db i id i newVal → i {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ -1 } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 { ^ -1 } {}
    ^ ( sqlite3_limit db_ptr id newVal )
}

// Install an authorizer callback to sandbox untrusted SQL. The closure
// is invoked by libsqlite during prepare as
//   ( auth action arg1 arg2 db_name trigger_or_view )
// and must return SQLITE_OK (allow), SQLITE_DENY (abort), or
// SQLITE_IGNORE (silently skip / NULL the column). The closure's
// compiled function has the exact C ABI libsqlite expects
// (`int(void* env, int action, const char*, const char*, const char*,
// const char*)`) — its env pointer is passed as pUserData. The handle
// keeps its own copy of the closure (docs/MEMORY.md §7.4) and drops it on
// `sqlite_clear_authorizer`, on a replacing `sqlite_set_authorizer`, or
// when the database closes, so the caller's closure can go out of scope.
@ sqlite_set_authorizer Database db ( @ i i s s s s ) auth → !v SqliteErr {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteOther } } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    // The handle's own copy; libsqlite is handed its function and env.
    : ?( @ i i s s s s ) fresh @ ?( @ i i s s s s ) { T auth }
    : i rc ?? fresh {
        T a → ( sqlite3_set_authorizer db_ptr # *u a 0 # *u a 1 )
        F → SQLITE_OK
    }
    = . h rc rc
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    // Installed: the copy replaces the one the handle kept, which goes
    // now that libsqlite no longer calls it.
    = . h auth fresh
    ^ @ !v SqliteErr { T 0 }
}

// Remove a previously-installed authorizer.
@ sqlite_clear_authorizer Database db → !v SqliteErr {
    : *DbState h ( __db_state db )
    ? == # i h 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteOther } } {}
    : *u db_ptr . h db
    ? == # i db_ptr 0 { ^ @ !v SqliteErr { F # SqliteErr SqliteUnsupported } } {}
    : i rc ( sqlite3_set_authorizer db_ptr # *u 0 # *u 0 )
    ? != rc SQLITE_OK { ^ @ !v SqliteErr { F ( __sqlite_err_of rc ) } } {}
    = . h auth @ ?( @ i i s s s s ) { F }
    ^ @ !v SqliteErr { T 0 }
}

// ── PRAGMA helpers (§16) ──────────────────────────────────────────

// PRAGMA journal_mode=WAL — write-ahead logging (better concurrency).
@ sqlite_journal_wal Database db → !i SqliteErr {
    ^ ( sqlite_exec db `PRAGMA journal_mode=WAL` )
}

// PRAGMA foreign_keys=ON|OFF — enforce FK constraints (off by default
// in SQLite for legacy reasons).
@ sqlite_foreign_keys Database db b on → !i SqliteErr {
    ^ ( sqlite_exec db ? on `PRAGMA foreign_keys=ON` `PRAGMA foreign_keys=OFF` )
}

// PRAGMA synchronous=<mode>. `mode` is "OFF" / "NORMAL" / "FULL" /
// "EXTRA". NORMAL is the recommended setting under WAL.
@ sqlite_synchronous Database db s mode → !i SqliteErr {
    : String sql ( string_with_cap 32 )
    ( string_push_str sql `PRAGMA synchronous=` )
    ( string_push_str sql mode )
    : !i SqliteErr r ( sqlite_exec db ( string_data sql ) )
    ^ r
}

// ── Auto-drop (Drop trait) ────────────────────────────────────────
//
// A scope-local Database / Statement closes itself at scope exit on
// every path. See the "Memory model" note at the top: do not also call
// sqlite_close / sqlite_finalize by hand on an auto-dropped handle.

// A connection and a statement are opaque C pointers, and `s` spells both
// a String and every FFI handle — so without these the compiler derives
// both as Send and a `sqlite3*` crosses a thread boundary without a word
// (docs/LIMITATIONS.md). SQLite's own rule is that a connection belongs to
// one thread at a time; the way to use one database from several threads
// is a connection per thread over the same file, with WAL for concurrent
// readers and `busy_timeout` for the writer. Marking the handles here
// makes that the compiler's rule rather than a comment in every caller: a
// struct holding one, a Vec of them and a closure capturing one are all
// refused at the boundary.
% NotSend Database {}

% NotSend Statement {}

% NotSync Database {}

% NotSync Statement {}

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
