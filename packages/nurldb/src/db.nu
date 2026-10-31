// packages/nurldb/src/db.nu — a database: its files, its catalog, its
// transactions, and what a crash leaves behind.
//
// A database is a directory:
//
//   data   the pages (page.nu); page 0 is the meta page
//   log    the write-ahead log (wal.nu)
//   clog   every transaction's fate as of the last checkpoint
//
// The meta page, after the common header:
//
//   32  u64 magic        "NURLDB01"
//   40  u32 version
//   44  u32 nurldb_tables root      the catalog's own tables (heap
//   48  u32 nurldb_columns root     tables like any other, made by the
//   52  u32 nurldb_indexes root     bootstrap transaction)
//   56  u64 next xid     as of the last checkpoint
//   64  u64 redo LSN     where recovery starts: every page change before
//                        it is in the data file
//   72  u64 next object id
//
// Open. An empty directory is bootstrapped. Otherwise the log's torn tail
// (a crash in the middle of an append) is cut off, every record from the
// redo LSN on is applied to a page whose LSN is below it (redo is
// idempotent), the commit and abort records update the clog, and every
// transaction the log does not see end is aborted — its versions become
// invisible, which is all a rollback has to do under MVCC. Then a
// checkpoint, and the log starts afresh.
//
// Checkpoint. Statements hold the checkpoint latch shared; a checkpoint
// takes it exclusively, so it sees no statement in flight: every dirty
// page is written (each after the log up to its LSN), the clog file is
// replaced, and the meta page records the new redo LSN. The first change
// to a page after a checkpoint logs the whole page (a full-page image),
// so a page torn by a power cut in the middle of its write is rebuilt by
// redo from that image rather than read back broken.
//
// Transaction ids are logged in blocks (R_META), and a checkpoint records
// the end of the last block as the next id: recovery hands out ids above
// every one a crashed run could have given away, even to a transaction
// that left nothing but its tuples.
//
// Locks, in the order they are taken: a table's lock (shared by every
// statement that changes rows, exclusive for CREATE INDEX), a unique
// key's lock, a row version's writer (txn_wait_for), then page latches
// — a statement never waits for a lock while it holds a latch.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/pfile.nu`
$ `page.nu`
$ `wal.nu`
$ `bufpool.nu`
$ `logrec.nu`
$ `value.nu`
$ `heap.nu`
$ `txn.nu`
$ `table.nu`
$ `keys.nu`
$ `btree.nu`

: i META_MAGIC 3544395820347757646
: i META_VERSION 1
: i M_MAGIC 32
: i M_VERSION 40
: i M_TABLES 44
: i M_COLUMNS 48
: i M_INDEXES 52
: i M_NEXT_XID 56
: i M_REDO 64
: i M_NEXT_OID 72

// Ids are logged this many at a time.
: i XID_BLOCK 1024
: i RM_XID_BOUND 1

// Lock resources: a table's, a unique key's (transaction ids are the
// negative ones, txn.nu).
: i RES_TABLE 1099511627776
: i RES_KEY 2199023255552
: i RES_KEY_MASK 1099511627775

// ── the catalog ────────────────────────────────────────────────────────

: ColDef {
    String name
    i ty
    b notnull
}

: IndexDef {
    String name
    Index ix
    b primary
}

// What a statement needs of a table: shared, never changed (CREATE INDEX
// makes a new one).
: TableMeta {
    i id
    String name
    ( Vec ColDef ) cols
    ( Vec i ) types
    Table t
    ( Vec IndexDef ) indexes
}

: TableInfo { ( Arc TableMeta ) a }

@ TableInfo_share TableInfo t → TableInfo { ^ @ TableInfo { ( arc_clone [TableMeta] . t a ) } }

@ TableInfo_drop sink TableInfo t → v {}

@ ti_meta TableInfo t → TableMeta { ^ ( arc_get [TableMeta] . t a ) }

: CatState { ( Vec TableInfo ) tables }

// ── the database ───────────────────────────────────────────────────────

: DbImpl {
    String dir
    Store st
    TxnMgr tm
    PFile data
    ( RwLocked CatState ) cat
    // Statements shared, a checkpoint exclusive.
    ( RwLocked i ) ckpt
    // DDL, one at a time.
    Mutex ddl
    Atomic next_oid
    Atomic xid_bound
    Table sys_tables
    Table sys_columns
    Table sys_indexes
}

: Db { ( Arc DbImpl ) a }

@ Db_share Db d → Db { ^ @ Db { ( arc_clone [DbImpl] . d a ) } }

@ Db_drop sink Db d → v {}

@ db_impl Db d → DbImpl { ^ ( arc_get [DbImpl] . d a ) }

@ db_store Db d → Store { ^ ( mem_dup . ( db_impl d ) st ) }

@ db_txnmgr Db d → TxnMgr { ^ ( mem_dup . ( db_impl d ) tm ) }

@ __path String dir s leaf → String { ^ ( string_concat ( string_clone dir ) ( string_from leaf ) ) }

// ── the system tables' rows ────────────────────────────────────────────

@ __types2 i a i b → ( Vec i ) { : ( Vec i ) t ( vec_new [i] ) ( vec_push [i] t a ) ( vec_push [i] t b ) ^ t }

@ sys_tables_types → ( Vec i ) {
    : ( Vec i ) t ( __types2 TY_INT TY_TEXT )
    ( vec_push [i] t TY_INT )
    ^ t
}

@ sys_columns_types → ( Vec i ) {
    : ( Vec i ) t ( __types2 TY_INT TY_INT )
    ( vec_push [i] t TY_TEXT ) ( vec_push [i] t TY_INT ) ( vec_push [i] t TY_BOOL )
    ^ t
}

@ sys_indexes_types → ( Vec i ) {
    : ( Vec i ) t ( __types2 TY_INT TY_INT )
    ( vec_push [i] t TY_TEXT ) ( vec_push [i] t TY_INT ) ( vec_push [i] t TY_TEXT )
    ( vec_push [i] t TY_BOOL ) ( vec_push [i] t TY_BOOL )
    ^ t
}

@ __vint Value v → i { ^ ?? v { VInt x → x _ → 0 } }

@ __vbool Value v → b { ^ ?? v { VBool x → x _ → F } }

@ __vtext Value v → String { ^ ?? v { VText s → ( string_clone s ) _ → ( string_new ) } }

// ── transactions ───────────────────────────────────────────────────────

: Txn {
    i xid
    Snapshot snap
    i cid
    b wrote
}

@ db_begin Db d → Txn {
    : DbImpl x ( db_impl d )
    : i xid ( txn_begin . x tm )
    // Ids are logged a block at a time, ahead of their use.
    ? >= xid ( atomic_load . x xid_bound ) {
        : i bound + xid XID_BLOCK
        : ( Vec u ) r ( rec_new R_META 13 )
        ( rec_u32 r RM_XID_BOUND )
        ( rec_u64 r bound )
        : i _l ( wal_append . . x st wal ( slice_from_vec [u] r ) )
        : i _m ( atomic_max . x xid_bound bound )
    } {}
    ^ @ Txn { xid ( txn_snapshot . x tm xid 0 ) 0 F }
}

// A statement of `x` begins: it sees what the earlier ones did.
@ db_statement inout Txn x → v {
    = . x cid + . x cid 1
    = . . x snap cid . x cid
}

// Commit under the checkpoint latch, shared: a checkpoint sees the commit
// whole — its record before the redo point and its clog entry in the file
// the checkpoint writes — or not at all (its record after the redo point,
// replayed). Interleaved, the record could fall before the redo point while
// the clog written still said running, and recovery aborted a commit that
// had been acknowledged.
@ db_commit Db d Txn x → v {
    : DbImpl dx ( db_impl d )
    : ( RGuard i ) g ( rw_read [i] . dx ckpt )
    ? . x wrote { ( txn_commit . dx tm . . dx st wal . x xid ) } { ( txn_finish_readonly . dx tm . x xid ) }
}

@ db_abort Db d Txn x → v {
    : DbImpl dx ( db_impl d )
    ( txn_abort . dx tm . . dx st wal . x xid )
}

@ __bt_image_db Store st PageWrite pw → v { : i _l ( log_page_image st pw ) }

@ __ctx Txn x → TxnCtx { ^ @ TxnCtx { . x xid . x cid } }

// Take `res` in `mode` for the transaction, or end the statement: the
// wait would have closed a cycle.
@ __lock Db d Txn x i res i mode → v {
    ? ! ( lock_acquire . ( db_impl d ) tm . x xid res mode ) { ( abort_deadlock ) } {}
}

// ── rows, with their indexes ───────────────────────────────────────────

// Make `row` fit the table: one value per column, of the column's type (an
// INT given for a REAL column becomes one), NOT NULL kept.
@ db_coerce_row TableMeta m ( Vec Value ) row → ( Vec Value ) {
    : i n ( vec_len [ColDef] . m cols )
    ? != ( vec_len [Value] row ) n {
        ( panic_with ( string_concat ( string_from `nurldb: ` ) ( string_concat ( string_clone . m name ) ( string_from ` has a different number of columns` ) ) ) )
    } {}
    : ( Vec Value ) out ( vec_with_cap [Value] n )
    : ~ i k 0
    ~ < k n {
        : ColDef c ( vec_at [ColDef] . m cols k )
        : Value v ( vec_at [Value] row k )
        : i vt ( val_type v )
        ? == vt 0 {
            ? . c notnull {
                ( panic_with ( string_concat ( string_from `nurldb: NULL in the NOT NULL column ` ) ( string_clone . c name ) ) )
            } {}
            ( vec_push [Value] out @ Value { VNull } )
        } {
            ? == vt . c ty { ( vec_push [Value] out ( val_clone v ) ) } {
                ? & == vt TY_INT == . c ty TY_REAL {
                    ( vec_push [Value] out @ Value { VReal # f ( __vint v ) } )
                } {
                    ( panic_with ( string_concat ( string_concat ( string_from `nurldb: a ` ) ( string_from ( ty_name vt ) ) ) ( string_concat ( string_from ` value for the column ` ) ( string_concat ( string_clone . c name ) ( string_concat ( string_from ` of type ` ) ( string_from ( ty_name . c ty ) ) ) ) ) ) )
                }
            }
        }
        = k + k 1
    }
    ^ out
}

// The bytes of `key` that name its columns (all but the TID).
@ __key_prefix ( Vec u ) key → ( Slice u ) { ^ ( slice_prefix [u] ( slice_from_vec [u] key ) - ( vec_len [u] key ) 8 ) }

@ __key_hash ( Slice u ) b i salt → i {
    : ~ i h ^^ -3750763034362895579 salt
    : ~ i k 0
    ~ < k ( slice_len [u] b ) {
        = h * ^^ h ( slice_byte b k ) 1099511628211
        = k + k 1
    }
    ^ h
}

// A unique index may hold `key` for `x` only when no other version with
// the same columns is live or may yet be. Every insert of a key takes the
// key's lock until its transaction ends, so no other running transaction
// is inserting it; a version another one is deleting is waited for — it
// is back if that one aborts.
@ __check_unique Db d Txn x IndexDef idef ( Vec u ) key → v {
    : DbImpl dx ( db_impl d )
    : ( Slice u ) pre ( __key_prefix key )
    : i res | RES_KEY & ( __key_hash pre ( index_id . idef ix ) ) RES_KEY_MASK
    ( __lock d x res LK_X )
    ~ T {
        : ~ i wait_for 0
        : ~ b dup F
        : ( Vec u ) lo ( key_lo pre )
        : ( Vec u ) hi ( key_hi pre )
        ( bt_scan . dx st . idef ix ( slice_from_vec [u] lo ) ( slice_from_vec [u] hi ) \ ( Slice u ) k → b {
            : i tid ( key_tid k )
            : PageRead pr ( pool_read . . dx st pool ( tid_pid tid ) )
            : ( Slice u ) tup ( hp_tuple ( page_bytes pr ) ( tid_slot tid ) )
            ? == ( slice_len [u] tup ) 0 { ^ T } {}
            : i xmin ( th_xmin tup )
            : i xmax ( th_xmax tup )
            : i smin ? == xmin . x xid XS_COMMITTED ( clog_get . dx tm xmin )
            ? == smin XS_ABORTED { ^ T } {}
            ? == smin XS_RUNNING { = wait_for xmin ^ F } {}
            ? == xmax . x xid { ^ T } {}
            : i smax ? == xmax 0 XS_ABORTED ( clog_get . dx tm xmax )
            ? == smax XS_COMMITTED { ^ T } {}
            ? == smax XS_RUNNING { = wait_for xmax ^ F } {}
            = dup T
            ^ F
        } )
        ? dup {
            ( panic_with ( string_concat ( string_from `nurldb: duplicate key in the unique index ` ) ( string_clone . idef name ) ) )
        } {}
        ? == wait_for 0 { ^ } {}
        ? ! ( txn_wait_for . dx tm . x xid wait_for ) { ( abort_deadlock ) } {}
    }
}

// Add the entries of the version `row` at `tid` to every index of the
// table.
@ __index_row Db d Txn x TableMeta m ( Vec Value ) row i tid → v {
    : DbImpl dx ( db_impl d )
    ~ idef . m indexes {
        : ( Vec u ) key ( index_key . idef ix row tid )
        ? ( index_unique . idef ix ) { ( __check_unique d x idef key ) } {}
        ( bt_insert . dx st . idef ix ( slice_from_vec [u] key ) )
    }
}

// Insert `row` (already coerced) into the table: its TID.
@ db_insert Db d inout Txn x TableInfo ti ( Vec Value ) row → i {
    : DbImpl dx ( db_impl d )
    : TableMeta m ( ti_meta ti )
    ( __lock d x + RES_TABLE . m id LK_S )
    = . x wrote T
    : i tid ( tbl_insert . dx st . m t ( __ctx x ) row )
    ( __index_row d x m row tid )
    ^ tid
}

// Replace the version at `tid` with `row`: the new version's TID, or -1
// when this statement already replaced it.
@ db_update Db d inout Txn x TableInfo ti i tid ( Vec Value ) row → i {
    : DbImpl dx ( db_impl d )
    : TableMeta m ( ti_meta ti )
    ( __lock d x + RES_TABLE . m id LK_S )
    = . x wrote T
    : i nt ( tbl_update . dx st . dx tm ( __ctx x ) . x snap . m t tid row )
    ? >= nt 0 { ( __index_row d x m row nt ) } {}
    ^ nt
}

@ db_delete Db d inout Txn x TableInfo ti i tid → b {
    : DbImpl dx ( db_impl d )
    : TableMeta m ( ti_meta ti )
    ( __lock d x + RES_TABLE . m id LK_S )
    = . x wrote T
    ^ ( tbl_delete . dx st . dx tm ( __ctx x ) . x snap . m t tid )
}

// ── catalog lookups ────────────────────────────────────────────────────

@ db_table Db d String name → ?TableInfo {
    : ( RGuard CatState ) g ( rw_read [CatState] . ( db_impl d ) cat )
    : CatState c ( rguard_get [CatState] g )
    ~ t . c tables {
        ? ( string_eq . ( ti_meta t ) name name ) { ^ @ ?TableInfo { T ( TableInfo_share t ) } } {}
    }
    ^ @ ?TableInfo { F }
}

@ db_table_names Db d → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : ( RGuard CatState ) g ( rw_read [CatState] . ( db_impl d ) cat )
    : CatState c ( rguard_get [CatState] g )
    ~ t . c tables { ( vec_push [String] out ( string_clone . ( ti_meta t ) name ) ) }
    ^ out
}

@ __cat_put Db d TableInfo ti → v {
    : ( WGuard CatState ) g ( rw_write [CatState] . ( db_impl d ) cat )
    ( wguard_update [CatState] g \ inout CatState c → v {
        : i n ( vec_len [TableInfo] . c tables )
        : ~ i k 0
        ~ < k n {
            ? == . ( ti_meta ( vec_at [TableInfo] . c tables k ) ) id . ( ti_meta ti ) id {
                ( vec_put [TableInfo] . c tables k ( TableInfo_share ti ) )
                ^
            } {}
            = k + k 1
        }
        ( vec_push [TableInfo] . c tables ( TableInfo_share ti ) )
    } )
}

// ── DDL ────────────────────────────────────────────────────────────────

@ __next_oid Db d → i { ^ ( atomic_add . ( db_impl d ) next_oid 1 ) }

// Persist the meta page's object counter (logged with the DDL's rows).
@ __meta_set_oid Db d → v {
    : DbImpl x ( db_impl d )
    : PageWrite pw ( pool_write . . x st pool 0 )
    ( slice_put_u64_le ( page_bytes_mut pw ) M_NEXT_OID ( atomic_load . x next_oid ) )
    ( __bt_image_db . x st pw )
}

@ db_find_col TableMeta m String name → i {
    : ~ i k 0
    ~ < k ( vec_len [ColDef] . m cols ) {
        ? ( string_eq . ( vec_at [ColDef] . m cols k ) name name ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// CREATE TABLE: its id. `pk`: the columns of its primary key (a unique
// index named <table>_pkey), none when empty.
@ db_create_table Db d String name ( Vec ColDef ) cols ( Vec String ) pk → !i String {
    : DbImpl dx ( db_impl d )
    ( mutex_lock . dx ddl )
    : ~ ! i String out @ !i String { F ( string_from `nurldb: CREATE TABLE failed` ) }
    : !v PanicInfo r ( recover \ → v {
        = out ( __create_table d name cols pk )
    } )
    ?? r { T _ → {} F p → { = out @ !i String { F ( string_clone . p msg ) } ( panic_info_free p ) } }
    ( mutex_unlock . dx ddl )
    ^ out
}

@ __create_table Db d String name ( Vec ColDef ) cols ( Vec String ) pk → !i String {
    : DbImpl dx ( db_impl d )
    ?? ( db_table d name ) { T _ → { ^ @ !i String { F ( string_concat ( string_from `nurldb: the table already exists: ` ) ( string_clone name ) ) } } F → {} }
    : ~ Txn x ( db_begin d )
    ( db_statement x )
    = . x wrote T
    : i id ( __next_oid d )
    : i root {
        : PageWrite pw ( heap_new_page . dx st )
        ( page_write_pid pw )
    }
    : ( Vec Value ) trow ( vec_new [Value] )
    ( vec_push [Value] trow @ Value { VInt id } ) ( vec_push [Value] trow @ Value { VText ( string_clone name ) } ) ( vec_push [Value] trow @ Value { VInt root } )
    : i _t ( tbl_insert . dx st . dx sys_tables ( __ctx x ) trow )
    : ( Vec i ) types ( vec_new [i] )
    : ~ i k 0
    ~ < k ( vec_len [ColDef] cols ) {
        : ColDef c ( vec_at [ColDef] cols k )
        : ( Vec Value ) crow ( vec_new [Value] )
        ( vec_push [Value] crow @ Value { VInt id } ) ( vec_push [Value] crow @ Value { VInt k } )
        ( vec_push [Value] crow @ Value { VText ( string_clone . c name ) } ) ( vec_push [Value] crow @ Value { VInt . c ty } )
        ( vec_push [Value] crow @ Value { VBool . c notnull } )
        : i _c ( tbl_insert . dx st . dx sys_columns ( __ctx x ) crow )
        ( vec_push [i] types . c ty )
        = k + k 1
    }
    : ( Vec ColDef ) cdefs ( vec_new [ColDef] )
    ~ c cols { ( vec_push [ColDef] cdefs @ ColDef { ( string_clone . c name ) . c ty . c notnull } ) }
    : TableInfo ti @ TableInfo { ( arc_new [TableMeta] @ TableMeta {
            id ( string_clone name ) cdefs ( vec_clone [i] types ) ( table_new id root root ( vec_clone [i] types ) ) ( vec_new [IndexDef] )
        } ) }
    ( __meta_set_oid d )
    ( db_commit d x )
    ( __cat_put d ti )
    ? > ( vec_len [String] pk ) 0 {
        ?? ( __create_index d ( string_concat ( string_clone name ) ( string_from `_pkey` ) ) name pk T T ) {
            T _ → {}
            F e → { ^ @ !i String { F e } }
        }
    } {}
    ^ @ !i String { T id }
}

// CREATE [UNIQUE] INDEX: its id. Every version in the table goes in (a
// transaction still running may commit it); a unique index refuses a
// table with two live versions of a key.
@ db_create_index Db d String name String table ( Vec String ) cols b unique → !i String {
    : DbImpl dx ( db_impl d )
    ( mutex_lock . dx ddl )
    : ~ ! i String out @ !i String { F ( string_from `nurldb: CREATE INDEX failed` ) }
    : !v PanicInfo r ( recover \ → v {
        = out ( __create_index d name table cols unique F )
    } )
    ?? r { T _ → {} F p → { = out @ !i String { F ( string_clone . p msg ) } ( panic_info_free p ) } }
    ( mutex_unlock . dx ddl )
    ^ out
}

@ __create_index Db d String name String table ( Vec String ) cols b unique b primary → !i String {
    : DbImpl dx ( db_impl d )
    : TableInfo ti ?? ( db_table d table ) { T t → t F → { ^ @ !i String { F ( string_concat ( string_from `nurldb: no such table: ` ) ( string_clone table ) ) } } }
    : TableMeta m ( ti_meta ti )
    : ( Vec i ) pos ( vec_new [i] )
    : ( Vec i ) types ( vec_new [i] )
    : String collist ( string_new )
    ~ cn cols {
        : i k ( db_find_col m cn )
        ? < k 0 { ^ @ !i String { F ( string_concat ( string_from `nurldb: no such column: ` ) ( string_clone cn ) ) } } {}
        ( vec_push [i] pos k )
        ( vec_push [i] types . ( vec_at [ColDef] . m cols k ) ty )
        ? > ( string_len collist ) 0 { ( string_push_char collist 44 ) } {}
        ( string_push_int collist k )
    }
    : ~ Txn x ( db_begin d )
    ( db_statement x )
    = . x wrote T
    // Writers to the table wait (and are waited for).
    ( __lock d x + RES_TABLE . m id LK_X )
    : i id ( __next_oid d )
    : i anchor ( bt_create . dx st )
    : Index ix ( index_new id . m id anchor ( bt_anchor_root . dx st anchor ) pos types unique )
    : IndexDef idef @ IndexDef { ( string_clone name ) ( Index_share ix ) primary }
    // Every version, checked for uniqueness by the same rule as an insert.
    ( tbl_scan_all . dx st . dx tm . m t \ i tid ( Vec Value ) row → b {
        : ( Vec u ) key ( index_key ix row tid )
        ? unique { ( __check_unique_build d x idef key tid ) } {}
        ( bt_insert . dx st ix ( slice_from_vec [u] key ) )
        ^ T
    } )
    : ( Vec Value ) irow ( vec_new [Value] )
    ( vec_push [Value] irow @ Value { VInt id } ) ( vec_push [Value] irow @ Value { VInt . m id } )
    ( vec_push [Value] irow @ Value { VText ( string_clone name ) } ) ( vec_push [Value] irow @ Value { VInt anchor } )
    ( vec_push [Value] irow @ Value { VText collist } ) ( vec_push [Value] irow @ Value { VBool unique } )
    ( vec_push [Value] irow @ Value { VBool primary } )
    : i _i ( tbl_insert . dx st . dx sys_indexes ( __ctx x ) irow )
    ( __meta_set_oid d )
    // The table with the index added: statements that start from now on
    // maintain it.
    : ( Vec IndexDef ) idx ( vec_new [IndexDef] )
    ~ e . m indexes { ( vec_push [IndexDef] idx @ IndexDef { ( string_clone . e name ) ( Index_share . e ix ) . e primary } ) }
    ( vec_push [IndexDef] idx idef )
    : ( Vec ColDef ) cdefs ( vec_new [ColDef] )
    ~ c . m cols { ( vec_push [ColDef] cdefs @ ColDef { ( string_clone . c name ) . c ty . c notnull } ) }
    : TableInfo nti @ TableInfo { ( arc_new [TableMeta] @ TableMeta { . m id ( string_clone . m name ) cdefs ( vec_clone [i] . m types ) ( Table_share . m t ) idx } ) }
    ( db_commit d x )
    ( __cat_put d nti )
    ^ @ !i String { T id }
}

// The build's uniqueness check: among the versions already in the index,
// is there another live one of the same key? (The build holds the table
// exclusively: nothing changes under it but transactions finishing.)
@ __check_unique_build Db d Txn x IndexDef idef ( Vec u ) key i tid → v {
    : DbImpl dx ( db_impl d )
    : TxnMgr tm . dx tm
    // Only a live version can collide.
    ? ! ( __version_live d tid ) { ^ } {}
    : ( Slice u ) pre ( __key_prefix key )
    : ~ b dup F
    : ( Vec u ) lo ( key_lo pre )
    : ( Vec u ) hi ( key_hi pre )
    ( bt_scan . dx st . idef ix ( slice_from_vec [u] lo ) ( slice_from_vec [u] hi ) \ ( Slice u ) k → b {
        ? ( __version_live d ( key_tid k ) ) { = dup T ^ F } {}
        ^ T
    } )
    ? dup { ( panic_with ( string_concat ( string_from `nurldb: duplicate key in the unique index ` ) ( string_clone . idef name ) ) ) } {}
}

// Is the version at `tid` committed and not deleted by a committed
// transaction (live for every new snapshot)?
@ __version_live Db d i tid → b {
    : DbImpl dx ( db_impl d )
    : PageRead pr ( pool_read . . dx st pool ( tid_pid tid ) )
    : ( Slice u ) tup ( hp_tuple ( page_bytes pr ) ( tid_slot tid ) )
    ? == ( slice_len [u] tup ) 0 { ^ F } {}
    ? != ( clog_get . dx tm ( th_xmin tup ) ) XS_COMMITTED { ^ F } {}
    : i xmax ( th_xmax tup )
    ^ | == xmax 0 != ( clog_get . dx tm xmax ) XS_COMMITTED
}

// ── open, recovery, checkpoint ─────────────────────────────────────────

: DbOpts {
    i frames  // the buffer pool's size, in pages
    b sync  // fdatasync the log at each commit
}

@ db_default_opts → DbOpts { ^ @ DbOpts { 4096 T } }

@ __meta_write_header ( Slice u ) p i tables i columns i indexes → v {
    ( slice_put_u64_le p M_MAGIC META_MAGIC )
    ( slice_put_u32_le p M_VERSION META_VERSION )
    ( slice_put_u32_le p M_TABLES tables )
    ( slice_put_u32_le p M_COLUMNS columns )
    ( slice_put_u32_le p M_INDEXES indexes )
}

// What recovery learned from the log.
: Replay {
    i applied
    i xid_max
    i end
}

// Apply the log from `from` to the pages of `st`; commits and aborts to
// `clog`.
@ __redo Store st String lpath i from ( Vec u ) clog → !Replay String {
    : ~ i applied 0
    : ~ i xid_max 0
    : !i String rr ( wal_replay ( string_data lpath ) from \ i lsn ( Slice u ) r → v {
        : i kind ( rec_kind r )
        ? | == kind R_COMMIT == kind R_ABORT {
            : i xid ( slice_u64_le r 1 )
            ? >= xid ( vec_len [u] clog ) { : b _g ( vec_resize_zeroed [u] clog + xid 4096 ) } {}
            ( vec_put [u] clog xid # u ? == kind R_COMMIT XS_COMMITTED XS_ABORTED )
            ? > xid xid_max { = xid_max xid } {}
            ^
        } {}
        ? == kind R_META {
            ? == ( slice_u32_le r 1 ) RM_XID_BOUND {
                : i b ( slice_u64_le r 5 )
                ? > b xid_max { = xid_max b } {}
            } {}
            ^
        } {}
        ? | == kind R_CHECKPOINT == kind 0 { ^ } {}
        // A page record.
        : i pid ( rec_pid r )
        ( pool_ensure_npages . st pool + pid 1 )
        : PageWrite pw ( pool_write . st pool pid )
        : ( Slice u ) p ( page_bytes_mut pw )
        ? < ( pg_lsn p ) lsn {
            ? | == kind R_BT_INSERT == kind R_BT_DELETE { ( bt_redo p r ) } { ( heap_redo p r ) }
            ( pg_set_lsn p lsn )
            = applied + applied 1
        } {}
    } )
    ?? rr {
        T end → { ^ @ !Replay String { T @ Replay { applied xid_max end } } }
        F e → { ^ @ !Replay String { F e } }
    }
}

// Open (or create) the database in directory `dir`: recovery first when
// it was not closed cleanly (always, in fact: after a clean close the log
// holds nothing to redo), then the log starts afresh.
@ db_open s dir DbOpts o → !Db String {
    ? ! ( file_exists dir ) {
        ?? ( dir_create_all dir ) { T _ → {} F _ → { ^ @ !Db String { F ( string_from `nurldb: cannot create the database directory` ) } } }
    } {}
    : String dirs ( string_from dir )
    : String dpath ( __path dirs `/data` )
    : String lpath ( __path dirs `/log` )
    ? ( file_exists ( string_data dpath ) ) {
        : i end ?? ( __recover dirs o ) { T e → e F e → { ^ @ !Db String { F e } } }
        ?? ( wal_reset ( string_data lpath ) end ) { T _ → {} F e → { ^ @ !Db String { F e } } }
        ^ ( __open dirs o F )
    } {}
    ^ ( __open dirs o T )
}

// The meta page's fields, read once.
: Meta {
    i troot
    i croot
    i iroot
    i next_xid
    i redo
    i next_oid
}

@ __read_meta Store st → !Meta String {
    : PageRead meta ( pool_read . st pool 0 )
    : ( Slice u ) mp ( page_bytes meta )
    ? != ( slice_u64_le mp M_MAGIC ) META_MAGIC { ^ @ !Meta String { F ( string_from `nurldb: not a nurldb database` ) } } {}
    ^ @ !Meta String { T @ Meta {
            ( slice_u32_le mp M_TABLES ) ( slice_u32_le mp M_COLUMNS ) ( slice_u32_le mp M_INDEXES )
            ( slice_u64_le mp M_NEXT_XID ) ( slice_u64_le mp M_REDO ) ( slice_u64_le mp M_NEXT_OID )
        } }
}

// Recovery, on its own pool and log: cut the torn tail, redo from the
// meta page's redo LSN, abort what did not end, checkpoint. The log's end
// comes back — everything before it is in the data file now.
@ __recover String dirs DbOpts o → !i String {
    : String dpath ( __path dirs `/data` )
    : String lpath ( __path dirs `/log` )
    : String cpath ( __path dirs `/clog` )
    : !i String sc ( wal_replay ( string_data lpath ) 0 \ i lsn ( Slice u ) r → v {} )
    ?? sc {
        T end → { ?? ( wal_truncate_to ( string_data lpath ) end ) { T _ → {} F e → { ^ @ !i String { F e } } } }
        F e → { ^ @ !i String { F e } }
    }
    : PFile df ?? ( pfile_open ( string_data dpath ) PFILE_RW ) { T h → h F _ → { ^ @ !i String { F ( string_from `nurldb: cannot open the data file` ) } } }
    : Wal w ?? ( wal_open ( string_data lpath ) . o sync ) { T x → x F e → { ^ @ !i String { F e } } }
    : Store st @ Store { ( pool_new ( mem_dup df ) ( mem_dup w ) . o frames ) ( mem_dup w ) }
    ( pool_set_recovering . st pool T )
    : Meta m ?? ( __read_meta st ) { T x → x F e → { ( wal_close w ) ^ @ !i String { F e } } }
    : ( Vec u ) clog ?? ( read_file_bytes ( string_data cpath ) ) { T v → v F _ → ( vec_new [u] ) }
    : Replay rp ?? ( __redo st lpath . m redo clog ) { T x → x F e → { ( wal_close w ) ^ @ !i String { F e } } }
    : ~ i next_xid . m next_xid
    ? >= . rp xid_max next_xid { = next_xid + . rp xid_max 1 } {}
    // A transaction the log did not see end: aborted.
    ? < ( vec_len [u] clog ) next_xid { : b _g ( vec_resize_zeroed [u] clog next_xid ) } {}
    : ~ i k + XID_BOOT 1
    ~ < k next_xid {
        ? == # i ( vec_at [u] clog k ) XS_RUNNING { ( vec_put [u] clog k # u XS_ABORTED ) } {}
        = k + k 1
    }
    ( pool_set_recovering . st pool F )
    : TxnMgr tm ( txnmgr_new next_xid clog )
    ( __ckpt_write st tm df dirs . m next_oid next_xid )
    : i end ( wal_next . st wal )
    ( wal_close w )
    ^ @ !i String { T end }
}

// Open the files for use (after recovery, or a new database).
@ __open String dirs DbOpts o b fresh → !Db String {
    : String dpath ( __path dirs `/data` )
    : String lpath ( __path dirs `/log` )
    : String cpath ( __path dirs `/clog` )
    : PFile df ?? ( pfile_open ( string_data dpath ) PFILE_CREATE ) { T h → h F _ → { ^ @ !Db String { F ( string_from `nurldb: cannot open the data file` ) } } }
    : Wal w ?? ( wal_open ( string_data lpath ) . o sync ) { T x → x F e → { ^ @ !Db String { F e } } }
    : Store st @ Store { ( pool_new ( mem_dup df ) ( mem_dup w ) . o frames ) ( mem_dup w ) }
    ? fresh {
        : PageWrite meta ( pool_new_page . st pool PT_META )
        : PageWrite t ( heap_new_page st )
        : PageWrite c ( heap_new_page st )
        : PageWrite ix ( heap_new_page st )
        : ( Slice u ) mp ( page_bytes_mut meta )
        ( __meta_write_header mp ( page_write_pid t ) ( page_write_pid c ) ( page_write_pid ix ) )
        ( slice_put_u64_le mp M_NEXT_XID 2 )
        ( slice_put_u64_le mp M_NEXT_OID 1 )
        ( __bt_image_db st meta )
    } {}
    : Meta m ?? ( __read_meta st ) { T x → x F e → { ( wal_close w ) ^ @ !Db String { F e } } }
    : ( Vec u ) clog ?? ( read_file_bytes ( string_data cpath ) ) { T v → v F _ → ( vec_new [u] ) }
    ( pool_set_redo . st pool ( wal_next . st wal ) )
    : TxnMgr tm ( txnmgr_new . m next_xid clog )
    : Table st_t ( table_new 0 . m troot ( __chain_last st . m troot ) ( sys_tables_types ) )
    : Table st_c ( table_new 0 . m croot ( __chain_last st . m croot ) ( sys_columns_types ) )
    : Table st_i ( table_new 0 . m iroot ( __chain_last st . m iroot ) ( sys_indexes_types ) )
    : Db d @ Db { ( arc_new [DbImpl] @ DbImpl {
            ( string_clone dirs ) st tm df
            ( rw_new [CatState] @ CatState { ( vec_new [TableInfo] ) } )
            ( rw_new [i] 0 ) ( mutex_new )
            ( atomic_new . m next_oid ) ( atomic_new . m next_xid )
            st_t st_c st_i
        } ) }
    ( __load_catalog d )
    ? fresh { ( db_checkpoint d ) } {}
    ^ @ !Db String { T d }
}

// The last page of the chain that starts at `root`.
@ __chain_last Store st i root → i {
    : ~ i pid root
    ~ T {
        : PageRead r ( pool_read . st pool pid )
        : i nx ( pg_next ( page_bytes r ) )
        ? == nx NO_PAGE { ^ pid } {}
        = pid nx
    }
}

// Rebuild the in-memory catalog from the system tables.
@ __load_catalog Db d → v {
    : DbImpl dx ( db_impl d )
    : Txn x ( db_begin d )
    : ( Vec ( Vec Value ) ) trows ( vec_new [( Vec Value )] )
    : ( Vec ( Vec Value ) ) crows ( vec_new [( Vec Value )] )
    : ( Vec ( Vec Value ) ) irows ( vec_new [( Vec Value )] )
    ( tbl_scan . dx st . dx tm . x snap . dx sys_tables \ i tid ( Vec Value ) row → b { ( vec_push [( Vec Value )] trows ( vec_clone_with [Value] row \ Value v → Value { ^ ( val_clone v ) } ) ) ^ T } )
    ( tbl_scan . dx st . dx tm . x snap . dx sys_columns \ i tid ( Vec Value ) row → b { ( vec_push [( Vec Value )] crows ( vec_clone_with [Value] row \ Value v → Value { ^ ( val_clone v ) } ) ) ^ T } )
    ( tbl_scan . dx st . dx tm . x snap . dx sys_indexes \ i tid ( Vec Value ) row → b { ( vec_push [( Vec Value )] irows ( vec_clone_with [Value] row \ Value v → Value { ^ ( val_clone v ) } ) ) ^ T } )
    ( db_commit d x )
    ~ tr trows {
        : i id ( __vint ( vec_at [Value] tr 0 ) )
        : i root ( __vint ( vec_at [Value] tr 2 ) )
        // Its columns, in order.
        : ~ i ncols 0
        ~ cr crows { ? == ( __vint ( vec_at [Value] cr 0 ) ) id { = ncols + ncols 1 } {} }
        : ( Vec ColDef ) cols ( vec_new [ColDef] )
        : ( Vec i ) types ( vec_new [i] )
        : ~ i k 0
        ~ < k ncols {
            ~ cr crows {
                ? & == ( __vint ( vec_at [Value] cr 0 ) ) id == ( __vint ( vec_at [Value] cr 1 ) ) k {
                    ( vec_push [ColDef] cols @ ColDef { ( __vtext ( vec_at [Value] cr 2 ) ) ( __vint ( vec_at [Value] cr 3 ) ) ( __vbool ( vec_at [Value] cr 4 ) ) } )
                    ( vec_push [i] types ( __vint ( vec_at [Value] cr 3 ) ) )
                } {}
            }
            = k + k 1
        }
        : ( Vec IndexDef ) idx ( vec_new [IndexDef] )
        ~ ir irows {
            ? == ( __vint ( vec_at [Value] ir 1 ) ) id {
                : i iid ( __vint ( vec_at [Value] ir 0 ) )
                : i anchor ( __vint ( vec_at [Value] ir 3 ) )
                : ( Vec i ) pos ( __parse_cols ( __vtext ( vec_at [Value] ir 4 ) ) )
                : ( Vec i ) itypes ( vec_new [i] )
                ~ ps pos { ( vec_push [i] itypes ( vec_at [i] types ps ) ) }
                : Index ix ( index_new iid id anchor ( bt_anchor_root . dx st anchor ) pos itypes ( __vbool ( vec_at [Value] ir 5 ) ) )
                ( vec_push [IndexDef] idx @ IndexDef { ( __vtext ( vec_at [Value] ir 2 ) ) ix ( __vbool ( vec_at [Value] ir 6 ) ) } )
            } {}
        }
        : TableInfo ti @ TableInfo { ( arc_new [TableMeta] @ TableMeta {
                id ( __vtext ( vec_at [Value] tr 1 ) ) cols ( vec_clone [i] types )
                ( table_new id root ( __chain_last . dx st root ) types ) idx
            } ) }
        ( __cat_put d ti )
    }
}

@ __parse_cols String s → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : ( Slice u ) b ( string_bytes s )
    : ~ i cur 0
    : ~ b any F
    : ~ i k 0
    ~ < k ( slice_len [u] b ) {
        : i c ( slice_byte b k )
        ? == c 44 { ( vec_push [i] out cur ) = cur 0 = any F } { = cur + * cur 10 - c 48 = any T }
        = k + k 1
    }
    ? any { ( vec_push [i] out cur ) } {}
    ^ out
}

// Write every dirty page and the clog, and move the redo point to the
// log's end: recovery starts there.
@ db_checkpoint Db d → v {
    : DbImpl dx ( db_impl d )
    : ( WGuard i ) g ( rw_write [i] . dx ckpt )
    ( __ckpt_write . dx st . dx tm . dx data . dx dir ( atomic_load . dx next_oid ) ( atomic_load . dx xid_bound ) )
}

// `xid_floor`: the ids handed out without a record of their own — those
// below the last block logged (db_begin) — end below it.
@ __ckpt_write Store st TxnMgr tm PFile data String dir i next_oid i xid_floor → v {
    : i redo ( wal_next . st wal )
    ( pool_flush_all . st pool )
    // The clog, replaced whole.
    : ( Vec u ) cl ( clog_copy tm )
    : String tmp ( __path dir `/clog.tmp` )
    : String cpath ( __path dir `/clog` )
    ?? ( write_file_bytes ( string_data tmp ) cl ) { T _ → {} F _ → { ( panic `nurldb: cannot write the clog` ) } }
    ?? ( fs_rename ( string_data tmp ) ( string_data cpath ) ) { T _ → {} F _ → { ( panic `nurldb: cannot replace the clog` ) } }
    {
        : PageWrite meta ( pool_write . st pool 0 )
        : ( Slice u ) mp ( page_bytes_mut meta )
        // The first id recovery may hand out: above every one the blocks
        // logged before this checkpoint cover, for redo starts after those
        // records. A transaction given one of them may have left nothing in
        // the log but its tuples; recovery gave its id to a new transaction,
        // whose commit brought them back (a transfer half done after a crash).
        : i nx ( txn_next_xid tm )
        ( slice_put_u64_le mp M_NEXT_XID ? > xid_floor nx xid_floor nx )
        ( slice_put_u64_le mp M_REDO redo )
        ( slice_put_u64_le mp M_NEXT_OID next_oid )
        ( __bt_image_db st meta )
    }
    ( wal_flush_all . st wal )
    ( pool_flush_all . st pool )
    ?? ( pfile_sync data ) { T _ → {} F _ → {} }
    ( pool_set_redo . st pool ( wal_next . st wal ) )
}

// Let go of the database: a checkpoint, and the log flusher stopped.
@ db_close Db d → v {
    ( db_checkpoint d )
    ( wal_close . . ( db_impl d ) st wal )
}

// The database as a killed process leaves it: the log's flusher writes
// what it was handed and stops, nothing is checkpointed, and the pages
// the buffer pool holds dirty are never written. db_open on the
// directory then recovers from the log, as after a crash — inside one
// process, for a test that crashes a server on a simulated network
// (std/net_sim.nu's netsim_crash) and restarts it. Consumes this handle;
// no session may still be using a copy (serve_on returns only once its
// connections have ended).
@ db_crash sink Db d → v { ( wal_close . . ( db_impl d ) st wal ) }

// Statements run under the checkpoint latch, shared.
@ db_stmt_latch Db d → ( RGuard i ) { ^ ( rw_read [i] . ( db_impl d ) ckpt ) }
