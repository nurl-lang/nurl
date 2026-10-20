// table_test.nu — rows through transactions, under threads.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/table_test.nu /tmp/tt && /tmp/tt
//
// Eight threads insert 16 000 rows into one table at once (its page chain
// grows under them, through a pool smaller than the table); a snapshot
// taken afterwards sees every row once, and none of an aborted
// transaction's. A delete is seen by later snapshots and not by one taken
// before it.
//
// Then the bank: 64 accounts, six threads moving money between random
// pairs while two threads total every balance. A transfer that meets a
// concurrent update of the same row is a serialization failure (or a
// deadlock): its transaction panics with page latches held, recover
// returns, the latches are released by the drop journal, and the
// transfer is retried. The readers' every total — each under its own
// snapshot, while transfers commit around it — is the starting total.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/pfile.nu`
$ `src/page.nu`
$ `src/wal.nu`
$ `src/bufpool.nu`
$ `src/heap.nu`
$ `src/txn.nu`
$ `src/table.nu`

: ~ i g_pass 0
: ~ i g_fail 0

: i NACC 64
: i START 1000

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
}

@ int_of Value v → i { ^ ?? v { VInt x → x _ → 0 } }

@ new_table Store st i id ( Vec i ) types → Table {
    : PageWrite pw ( heap_new_page st )
    : i root ( page_write_pid pw )
    ^ ( table_new id root root types )
}

// How many rows `snap` sees in `t`, and the sum of their column `col`.
@ count_rows Store st TxnMgr m Snapshot snap Table t → i {
    : ~ i n 0
    ( tbl_scan st m snap t \ i tid ( Vec Value ) row → b { = n + n 1 ^ T } )
    ^ n
}

@ sum_col Store st TxnMgr m Snapshot snap Table t i col → i {
    : ~ i total 0
    ( tbl_scan st m snap t \ i tid ( Vec Value ) row → b { = total + total ( int_of ( vec_at [Value] row col ) ) ^ T } )
    ^ total
}

// The TID and balance of account `id` as `snap` sees it.
@ find_acct Store st TxnMgr m Snapshot snap Table t i id → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    ( tbl_scan st m snap t \ i tid ( Vec Value ) row → b {
        ? == ( int_of ( vec_at [Value] row 0 ) ) id {
            ( vec_push [i] out tid )
            ( vec_push [i] out ( int_of ( vec_at [Value] row 1 ) ) )
            ^ F
        } {}
        ^ T
    } )
    ^ out
}

@ acct_row i id i bal → ( Vec Value ) {
    : ( Vec Value ) r ( vec_new [Value] )
    ( vec_push [Value] r @ Value { VInt id } )
    ( vec_push [Value] r @ Value { VInt bal } )
    ^ r
}

// Move `amt` from account `a` to `b` in transaction `xid`.
@ transfer Store st TxnMgr m Table t i xid i a i b i amt → v {
    : Snapshot snap ( txn_snapshot m xid 1 )
    : TxnCtx x @ TxnCtx { xid 1 }
    : ( Vec i ) fa ( find_acct st m snap t a )
    : ( Vec i ) fb ( find_acct st m snap t b )
    : i _a ( tbl_update st m x snap t ( vec_at [i] fa 0 ) ( acct_row a - ( vec_at [i] fa 1 ) amt ) )
    : i _b ( tbl_update st m x snap t ( vec_at [i] fb 0 ) ( acct_row b + ( vec_at [i] fb 1 ) amt ) )
}

@ main → i {
    : s dpath `/tmp/nurldb_table_test.db`
    : s lpath `/tmp/nurldb_table_test.log`
    ?? ( file_delete dpath ) { T _ → {} F _ → {} }
    ?? ( file_delete lpath ) { T _ → {} F _ → {} }
    : PFile df ?? ( pfile_open dpath PFILE_CREATE ) { T h → h F _ → { ^ 1 } }
    : Wal w ?? ( wal_open lpath F ) { T x → x F _ → { ^ 1 } }
    : Store st @ Store { ( pool_new df ( mem_dup w ) 48 ) ( mem_dup w ) }
    : TxnMgr m ( txnmgr_new 2 ( vec_new [u] ) )
    // Page 0 is the database's own (its meta page): no chain starts there.
    { : PageWrite meta ( pool_new_page . st pool PT_META ) }

    // ── eight inserters ──
    : ( Vec i ) ty ( vec_new [i] )
    ( vec_push [i] ty TY_INT ) ( vec_push [i] ty TY_INT ) ( vec_push [i] ty TY_TEXT )
    : Table t ( new_table st 1 ty )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i th 0
    ~ < th 8 {
        : i me th
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 2000 {
                : i xid ( txn_begin m )
                : TxnCtx x @ TxnCtx { xid 0 }
                : ~ i j 0
                ~ < j 50 {
                    : ( Vec Value ) row ( vec_new [Value] )
                    ( vec_push [Value] row @ Value { VInt me } )
                    ( vec_push [Value] row @ Value { VInt + k j } )
                    ( vec_push [Value] row @ Value { VText ( string_from `a row of text` ) } )
                    : i _t ( tbl_insert st t x row )
                    = j + j 1
                }
                ( txn_commit m w xid )
                = k + k 50
            }
        } )
        ?? r { T h → { ( vec_push [Thread] ts h ) } F _ → {} }
        = th + th 1
    }
    ~ h ts { ( thread_join h ) }
    : i ab ( txn_begin m )
    : i _t ( tbl_insert st t @ TxnCtx { ab 0 } ( acct_row 99 99 ) )
    ( txn_abort m w ab )

    : i rx ( txn_begin m )
    : Snapshot s1 ( txn_snapshot m rx 0 )
    ( check `a snapshot sees all 16 000 rows, and not the aborted one` == ( count_rows st m s1 t ) 16000 )
    : ~ i pages 0
    : ~ i pid ( table_root t )
    ~ != pid NO_PAGE {
        = pages + pages 1
        : PageRead pr ( pool_read . st pool pid )
        = pid ( pg_next ( page_bytes pr ) )
    }
    ( check `the chain grew past the pool (48 frames)` > pages 48 )
    ( nurl_print `  (` ) ( nurl_print_int pages ) ( nurl_print ` pages, pool writes ` ) ( nurl_print_int ( pool_writes . st pool ) ) ( nurl_println `)` )

    // ── a delete, and who sees it ──
    : i dx ( txn_begin m )
    : Snapshot ds ( txn_snapshot m dx 1 )
    : ~ i deleted 0
    ( tbl_scan st m ds t \ i tid ( Vec Value ) row → b {
        ? == ( int_of ( vec_at [Value] row 0 ) ) 3 {
            ? ( tbl_delete st m @ TxnCtx { dx 1 } ds t tid ) { = deleted + deleted 1 } {}
        } {}
        ^ T
    } )
    ( txn_commit m w dx )
    ( check `one thread's 2 000 rows deleted` == deleted 2000 )
    : i rx2 ( txn_begin m )
    : Snapshot s2 ( txn_snapshot m rx2 0 )
    ( check `a later snapshot does not see them` == ( count_rows st m s2 t ) 14000 )
    ( check `the earlier snapshot still does` == ( count_rows st m s1 t ) 16000 )
    ( txn_finish_readonly m rx )
    ( txn_finish_readonly m rx2 )

    // ── the bank ──
    : ( Vec i ) aty ( vec_new [i] )
    ( vec_push [i] aty TY_INT ) ( vec_push [i] aty TY_INT )
    : Table bank ( new_table st 2 aty )
    : i bx ( txn_begin m )
    : ~ i a 0
    ~ < a NACC { : i _i ( tbl_insert st bank @ TxnCtx { bx 0 } ( acct_row a START ) ) = a + a 1 }
    ( txn_commit m w bx )

    : Atomic retries ( atomic_new 0 )
    : Atomic moved ( atomic_new 0 )
    : Atomic totals ( atomic_new 0 )
    : Atomic bad ( atomic_new 0 )
    : Atomic writers ( atomic_new 6 )
    : ( Vec Thread ) bt ( vec_new [Thread] )
    = th 0
    ~ < th 8 {
        : i me th
        : !Thread ThreadErr r ( thread_spawn \ → v {
            ? >= me 6 {
                ~ > ( atomic_load writers ) 0 {
                    : i rx3 ( txn_begin m )
                    : Snapshot rs ( txn_snapshot m rx3 0 )
                    ? != ( sum_col st m rs bank 1 ) * NACC START { ( atomic_add bad 1 ) } {}
                    ( txn_finish_readonly m rx3 )
                    ( atomic_add totals 1 )
                }
                ^
            } {}
            : Rng g ( rng_seed + 77 me )
            : ~ i done 0
            ~ < done 150 {
                : i fa ( rng_below g NACC )
                : i fb0 ( rng_below g - NACC 1 )
                : i fb ? >= fb0 fa + fb0 1 fb0
                : i amt + 1 ( rng_below g 50 )
                : i xid ( txn_begin m )
                : ~ b ok F
                : !v PanicInfo pr ( recover \ → v {
                    ( transfer st m bank xid fa fb amt )
                    = ok T
                } )
                ?? pr { T _ → {} F p → { ( panic_info_free p ) } }
                ? ok {
                    ( txn_commit m w xid )
                    ( atomic_add moved amt )
                    = done + done 1
                } {
                    ( txn_abort m w xid )
                    ( atomic_add retries 1 )
                }
            }
            ( atomic_sub writers 1 )
        } )
        ?? r { T h → { ( vec_push [Thread] bt h ) } F _ → {} }
        = th + th 1
    }
    ~ h bt { ( thread_join h ) }
    : i fx ( txn_begin m )
    : Snapshot fs ( txn_snapshot m fx 0 )
    ( check `the total is what it was` == ( sum_col st m fs bank 1 ) * NACC START )
    ( check `every account is still there once` == ( count_rows st m fs bank ) NACC )
    ( check `no reader ever saw a different total` == ( atomic_load bad ) 0 )
    ( check `the readers totalled while transfers ran` > ( atomic_load totals ) 0 )
    ( check `conflicts happened, and were retried` > ( atomic_load retries ) 0 )
    ( txn_finish_readonly m fx )
    ( nurl_print `  (900 transfers, ` ) ( nurl_print_int ( atomic_load retries ) ) ( nurl_print ` retried, ` )
    ( nurl_print_int ( atomic_load totals ) ) ( nurl_print ` totals, ` ) ( nurl_print_int ( txn_deadlocks m ) ) ( nurl_println ` deadlocks)` )

    ( pool_flush_all . st pool )
    ( wal_close w )
    ?? ( file_delete dpath ) { T _ → {} F _ → {} }
    ?? ( file_delete lpath ) { T _ → {} F _ → {} }
    ( nurl_print `table_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}
