// db_test.nu — a database: tables and indexes in the catalog, unique keys
// under threads, and what a reopen finds.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/db_test.nu /tmp/dt && /tmp/dt
//
// A table with a primary key and a second index; rows go in through
// transactions and come back through a scan and through each index. A
// duplicate key is refused (the statement panics, recover hands back the
// message, the transaction aborts). A transaction inserting a key another
// one inserted but has not committed waits for it: when that one aborts,
// the waiter's insert goes in. Eight threads insert 4 000 rows while two
// race them for the same keys — every key ends up there exactly once.
// CREATE INDEX on a populated table indexes every row. Closed and opened
// again, the catalog, the rows and the indexes are all there.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/io.nu`
$ `src/db.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
    ( flush )
}

@ col s name i ty b nn → ColDef { ^ @ ColDef { ( string_from name ) ty nn } }

@ row3 i id s owner i bal → ( Vec Value ) {
    : ( Vec Value ) r ( vec_new [Value] )
    ( vec_push [Value] r @ Value { VInt id } )
    ( vec_push [Value] r @ Value { VText ( string_from owner ) } )
    ( vec_push [Value] r @ Value { VInt bal } )
    ^ r
}

@ table_of Db d s name → TableInfo {
    ^ ?? ( db_table d ( string_from name ) ) { T t → t F → { ( panic `no table` ) ^ ( panic_unreachable_ti ) } }
}

@ panic_unreachable_ti → TableInfo { ( panic `unreachable` ) ^ ( panic_unreachable_ti ) }

// Rows a fresh snapshot sees in `name`.
@ count Db d s name → i {
    : TableInfo ti ( table_of d name )
    : Txn x ( db_begin d )
    : ~ i n 0
    ( tbl_scan ( db_store d ) ( db_txnmgr d ) . x snap . ( ti_meta ti ) t \ i tid ( Vec Value ) row → b { = n + n 1 ^ T } )
    ( db_commit d x )
    ^ n
}

// Rows a fresh snapshot sees through the index `k` of `name` for INT `v`
// (its entries point at every version; the snapshot decides).
@ index_hits Db d s name i k i v → i {
    : TableInfo ti ( table_of d name )
    : IndexDef idef ( vec_at [IndexDef] . ( ti_meta ti ) indexes k )
    : Txn x ( db_begin d )
    : ( Vec u ) pre ( vec_new [u] )
    ( key_put pre @ Value { VInt v } TY_INT )
    : ( Vec u ) lo ( key_lo ( slice_from_vec [u] pre ) )
    : ( Vec u ) hi ( key_hi ( slice_from_vec [u] pre ) )
    : ~ i n 0
    ( bt_scan ( db_store d ) . idef ix ( slice_from_vec [u] lo ) ( slice_from_vec [u] hi ) \ ( Slice u ) key → b {
        ?? ( tbl_fetch ( db_store d ) ( db_txnmgr d ) . x snap . ( ti_meta ti ) t ( key_tid key ) ) { T _ → { = n + n 1 } F → {} }
        ^ T
    } )
    ( db_commit d x )
    ^ n
}

// Insert one row in a transaction of its own: "" or the error.
@ insert_one Db d s table i id s owner i bal → String {
    : TableInfo ti ( table_of d table )
    : ~ Txn x ( db_begin d )
    ( db_statement x )
    : ~ String err ( string_new )
    : !v PanicInfo r ( recover \ → v {
        : i _t ( db_insert d x ti ( row3 id owner bal ) )
    } )
    ?? r {
        T _ → { ( db_commit d x ) }
        F p → { = err ( string_clone . p msg ) ( panic_info_free p ) ( db_abort d x ) }
    }
    ^ err
}

@ main → i {
    : s dir `/tmp/nurldb_db_test`
    ( rm_rf dir )
    : Db d ?? ( db_open dir ( db_default_opts ) ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }

    // ── DDL ──
    : ( Vec ColDef ) cols ( vec_new [ColDef] )
    ( vec_push [ColDef] cols ( col `id` TY_INT T ) )
    ( vec_push [ColDef] cols ( col `owner` TY_TEXT T ) )
    ( vec_push [ColDef] cols ( col `balance` TY_INT F ) )
    : ( Vec String ) pk ( vec_new [String] )
    ( vec_push [String] pk ( string_from `id` ) )
    : !i String ct ( db_create_table d ( string_from `accounts` ) cols pk )
    ( check `CREATE TABLE with a primary key` ?? ct { T _ → T F _ → F } )
    : ( Vec ColDef ) cols2 ( vec_new [ColDef] )
    ( vec_push [ColDef] cols2 ( col `id` TY_INT T ) )
    : !i String ct2 ( db_create_table d ( string_from `accounts` ) cols2 ( vec_new [String] ) )
    ( check `a second table of the same name is refused` ?? ct2 { T _ → F F _ → T } )

    // ── rows ──
    : ~ i k 0
    ~ < k 1000 {
        : String e ( insert_one d `accounts` k `someone` 100 )
        ? > ( string_len e ) 0 { ( nurl_println ( string_data e ) ) } {}
        = k + k 1
    }
    ( check `1 000 rows` == ( count d `accounts` ) 1000 )
    ( check `the primary key finds a row` == ( index_hits d `accounts` 0 500 ) 1 )
    : String dup ( insert_one d `accounts` 500 `again` 1 )
    ( check `a duplicate key is refused` ( string_starts dup `nurldb: duplicate key` ) )
    ( check `and the refused row is not there` == ( count d `accounts` ) 1000 )
    : String bad ( insert_one d `accounts` 5000 `x` 0 )
    ( check `a row after the refusal goes in` == ( string_len bad ) 0 )

    // ── a waiter for a key another transaction holds ──
    : TableInfo ti ( table_of d `accounts` )
    : ~ Txn holder ( db_begin d )
    ( db_statement holder )
    : i _h ( db_insert d holder ti ( row3 7000 `first` 1 ) )
    : Atomic state ( atomic_new 0 )
    : !Thread ThreadErr wt ( thread_spawn \ → v {
        : String e ( insert_one d `accounts` 7000 `second` 2 )
        ( atomic_store state ? == ( string_len e ) 0 1 2 )
    } )
    ( sleep_ms 30 )
    ( check `an insert of a key a running transaction holds waits` == ( atomic_load state ) 0 )
    ( db_abort d holder )
    ?? wt { T h → { ( thread_join h ) } F _ → {} }
    ( check `and goes in once that one aborts` == ( atomic_load state ) 1 )

    // ── threads ──
    : Atomic dups ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 10 {
        : i me t
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i j 0
            ~ < j 500 {
                // Threads 8 and 9 race 0 and 1 for the same keys.
                : i id + 10000 + * j 8 ? >= me 8 - me 8 me
                : String e ( insert_one d `accounts` id `thread` me )
                ? > ( string_len e ) 0 { ( atomic_add dups 1 ) } {}
                = j + j 1
            }
        } )
        ?? r { T h → { ( vec_push [Thread] ts h ) } F _ → {} }
        = t + t 1
    }
    ~ h ts { ( thread_join h ) }
    ( check `4 000 keys from ten threads, each once` == ( count d `accounts` ) + 1002 4000 )
    ( check `every racing insert either went in or was a duplicate` == ( atomic_load dups ) 1000 )

    // ── an index on a populated table ──
    : ( Vec String ) bc ( vec_new [String] )
    ( vec_push [String] bc ( string_from `balance` ) )
    : !i String ci ( db_create_index d ( string_from `by_balance` ) ( string_from `accounts` ) bc F )
    ( check `CREATE INDEX` ?? ci { T _ → T F _ → F } )
    ( check `it holds every row` == ( index_hits d `accounts` 1 100 ) 1000 )

    // ── reopen ──
    ( db_close d )
    : Db d2 ?? ( db_open dir ( db_default_opts ) ) { T x → x F e → { ( nurl_println ( string_data e ) ) ^ 1 } }
    ( check `reopened: the rows are there` == ( count d2 `accounts` ) 5002 )
    ( check `reopened: both indexes are there` == ( vec_len [IndexDef] . ( ti_meta ( table_of d2 `accounts` ) ) indexes ) 2 )
    ( check `reopened: the primary key still finds a row` == ( index_hits d2 `accounts` 0 7000 ) 1 )
    : String dup2 ( insert_one d2 `accounts` 7000 `third` 3 )
    ( check `reopened: the key is still unique` ( string_starts dup2 `nurldb: duplicate key` ) )
    ( db_close d2 )
    ( rm_rf dir )
    ( nurl_print `db_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}

@ string_starts String s s prefix → b {
    : i n ( nurl_str_len prefix )
    ? < ( string_len s ) n { ^ F } {}
    ^ != 0 ( nurl_str_eq ( nurl_str_slice ( string_data s ) 0 n ) prefix )
}

@ rm_rf s dir → v {
    ?? ( file_delete ( nurl_str_cat dir `/data` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/log` ) ) { T _ → {} F _ → {} }
    ?? ( file_delete ( nurl_str_cat dir `/clog` ) ) { T _ → {} F _ → {} }
}
