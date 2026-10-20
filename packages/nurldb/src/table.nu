// packages/nurldb/src/table.nu — rows of a table, through transactions.
//
//   ( tbl_insert st t x row )              → i    the new version's TID
//   ( tbl_scan st tm snap t f )            → v    f gets (tid, row) for each
//                                                  version the snapshot sees;
//                                                  F from f stops the scan
//   ( tbl_fetch st tm snap t tid )         → ?( Vec Value )
//   ( tbl_update st tm x snap t tid row )  → i    the new version's TID, or
//                                                  -1: not there to update
//   ( tbl_delete st tm x snap t tid )      → b    F: not there to delete
//
// An update or a delete first CLAIMS the version it replaces: under the
// page's write latch it sets the version's xmax to its own transaction.
// A version already claimed by a transaction that is still running is
// waited for (the latch let go first: nobody waits holding a latch), and
// then looked at again. One claimed by a transaction that committed after
// this one's snapshot was taken is a conflict this transaction cannot
// resolve under snapshot isolation: it panics with a serialization
// failure, which the statement's recover turns into an abort (db.nu). A
// wait that would close a cycle of waiting transactions is a deadlock,
// and ends the same way.
//
// A scan never calls out while it holds a latch: it decodes a page's
// visible rows, lets the page go, and then hands them to `f` — which may
// itself read and change the table (an UPDATE scans what it changes).

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/panic.nu`
$ `page.nu`
$ `bufpool.nu`
$ `heap.nu`
$ `txn.nu`
$ `value.nu`

// A table as the storage layer knows it: its pages and its row shape.
// Shared by every thread working on the table.
: TableImpl {
    i id
    i root  // the first heap page
    Atomic last  // the page inserts go to
    ( Locked i ) grow  // the same, held while the chain grows by a page
    ( Vec i ) types  // column types, for decoding
}

: Table { ( Arc TableImpl ) a }

@ Table_share Table t → Table { ^ @ Table { ( arc_clone [TableImpl] . t a ) } }

@ Table_drop sink Table t → v {}

@ table_new i id i root i last ( Vec i ) types → Table {
    ^ @ Table { ( arc_new [TableImpl] @ TableImpl { id root ( atomic_new last ) ( locked_new [i] last ) types } ) }
}

@ table_id Table t → i { ^ . ( arc_get [TableImpl] . t a ) id }

@ table_root Table t → i { ^ . ( arc_get [TableImpl] . t a ) root }

@ table_last Table t → i { ^ ( atomic_load . ( arc_get [TableImpl] . t a ) last ) }

// A transaction's statement: who writes, and in which command.
: TxnCtx {
    i xid
    i cid
}

// A version claim's verdict.
: i CLAIM_OK 0
: i CLAIM_MINE 1
: i CLAIM_GONE 2

@ tbl_insert Store st Table tb TxnCtx x ( Vec Value ) row → i {
    : TableImpl t ( arc_get [TableImpl] . tb a )
    : ( Vec u ) tup ( tuple_build . x xid . x cid row )
    : ( Slice u ) tv ( slice_from_vec [u] tup )
    ? > ( slice_len [u] tv ) - - PAGE_SIZE HP_SLOTS 8 { ( panic `nurldb: a row larger than a page` ) } {}
    ~ T {
        : i pid ( atomic_load . t last )
        {
            : PageWrite pw ( pool_write . st pool pid )
            : i slot ( heap_put st pw tv )
            ? >= slot 0 { ^ ( tid_of pid slot ) } {}
        }
        // Full: grow the chain (unless another thread just did).
        ( locked_update [i] . t grow \ inout i last → v {
            ? == last pid {
                : PageWrite np ( heap_new_page st )
                : i npid ( page_write_pid np )
                {
                    : PageWrite old ( pool_write . st pool pid )
                    ( heap_link st old npid )
                }
                = last npid
                ( atomic_store . t last npid )
            } {}
        } )
    }
}

// The versions of page `pid` of `t` that `snap` sees, appended to `rows`
// (their TIDs to `tids`): the page's latch is let go before this returns.
// The next page of the chain comes back (NO_PAGE at its end).
@ tbl_page_rows Store st TxnMgr tm Snapshot snap Table tb i pid inout ( Vec ( Vec Value ) ) rows inout ( Vec i ) tids → i {
    : TableImpl t ( arc_get [TableImpl] . tb a )
    : PageRead pr ( pool_read . st pool pid )
    : ( Slice u ) p ( page_bytes pr )
    : i ns ( hp_nslots p )
    : ~ i k 0
    ~ < k ns {
        : ( Slice u ) tup ( hp_tuple p k )
        ? > ( slice_len [u] tup ) 0 {
            ? ( tuple_visible tm snap tup ) {
                ( vec_push [i] tids ( tid_of pid k ) )
                ( vec_push [( Vec Value )] rows ( tuple_row tup . t types ) )
            } {}
        } {}
        = k + k 1
    }
    ^ ( pg_next p )
}

// Every page of the chain, in order (a parallel scan deals them out).
@ tbl_pages Store st Table tb → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : ~ i pid ( table_root tb )
    ~ != pid NO_PAGE {
        ( vec_push [i] out pid )
        : PageRead pr ( pool_read . st pool pid )
        = pid ( pg_next ( page_bytes pr ) )
    }
    ^ out
}

@ table_types Table tb → ( Vec i ) { ^ ( vec_clone [i] . ( arc_get [TableImpl] . tb a ) types ) }

// Call `f` with each version of `t` that `snap` sees, page by page.
@ tbl_scan Store st TxnMgr tm Snapshot snap Table tb ( @ b i ( Vec Value ) ) f → v {
    : TableImpl t ( arc_get [TableImpl] . tb a )
    : ~ i pid . t root
    ~ != pid NO_PAGE {
        : ( Vec i ) tids ( vec_new [i] )
        : ( Vec ( Vec Value ) ) rows ( vec_new [( Vec Value )] )
        {
            : PageRead pr ( pool_read . st pool pid )
            : ( Slice u ) p ( page_bytes pr )
            : i ns ( hp_nslots p )
            : ~ i k 0
            ~ < k ns {
                : ( Slice u ) tup ( hp_tuple p k )
                ? > ( slice_len [u] tup ) 0 {
                    ? ( tuple_visible tm snap tup ) {
                        ( vec_push [i] tids ( tid_of pid k ) )
                        ( vec_push [( Vec Value )] rows ( tuple_row tup . t types ) )
                    } {}
                } {}
                = k + k 1
            }
            = pid ( pg_next p )
        }
        : i n ( vec_len [i] tids )
        : ~ i k 0
        ~ < k n {
            ? ! ( f ( vec_at [i] tids k ) ( vec_at [( Vec Value )] rows k ) ) { ^ } {}
            = k + k 1
        }
    }
}

// Call `f` with every version in `t` whose maker did not abort, seen or
// not by any snapshot: what an index built now must hold (a transaction
// still running may commit its versions).
@ tbl_scan_all Store st TxnMgr tm Table tb ( @ b i ( Vec Value ) ) f → v {
    : TableImpl t ( arc_get [TableImpl] . tb a )
    : ~ i pid . t root
    ~ != pid NO_PAGE {
        : ( Vec i ) tids ( vec_new [i] )
        : ( Vec ( Vec Value ) ) rows ( vec_new [( Vec Value )] )
        {
            : PageRead pr ( pool_read . st pool pid )
            : ( Slice u ) p ( page_bytes pr )
            : i ns ( hp_nslots p )
            : ~ i k 0
            ~ < k ns {
                : ( Slice u ) tup ( hp_tuple p k )
                ? > ( slice_len [u] tup ) 0 {
                    ? != ( clog_get tm ( th_xmin tup ) ) XS_ABORTED {
                        ( vec_push [i] tids ( tid_of pid k ) )
                        ( vec_push [( Vec Value )] rows ( tuple_row tup . t types ) )
                    } {}
                } {}
                = k + k 1
            }
            = pid ( pg_next p )
        }
        : ~ i k 0
        ~ < k ( vec_len [i] tids ) {
            ? ! ( f ( vec_at [i] tids k ) ( vec_at [( Vec Value )] rows k ) ) { ^ } {}
            = k + k 1
        }
    }
}

// The row at `tid` if `snap` sees that version.
@ tbl_fetch Store st TxnMgr tm Snapshot snap Table tb i tid → ?( Vec Value ) {
    : TableImpl t ( arc_get [TableImpl] . tb a )
    : PageRead pr ( pool_read . st pool ( tid_pid tid ) )
    : ( Slice u ) tup ( hp_tuple ( page_bytes pr ) ( tid_slot tid ) )
    ? | == ( slice_len [u] tup ) 0 ! ( tuple_visible tm snap tup ) { ^ @ ?( Vec Value ) { F } } {}
    ^ @ ?( Vec Value ) { T ( tuple_row tup . t types ) }
}

@ abort_serialization → v {
    ( panic `nurldb: could not serialize access due to a concurrent update` )
}

@ abort_deadlock → v {
    ( panic `nurldb: deadlock detected — this transaction was chosen to abort` )
}

// Claim the version at `tid` for `x` (set its xmax): CLAIM_OK, CLAIM_MINE
// when this statement's own transaction already did, or CLAIM_GONE when the
// version is not there. Waits out a running claimant; panics on a
// conflict that snapshot isolation cannot resolve.
@ tbl_claim Store st TxnMgr tm TxnCtx x Snapshot snap i tid → i {
    ~ T {
        : ~ i holder 0
        {
            : PageWrite pw ( pool_write . st pool ( tid_pid tid ) )
            : ( Slice u ) p ( page_bytes_mut pw )
            : ( Slice u ) tup ( hp_tuple p ( tid_slot tid ) )
            ? == ( slice_len [u] tup ) 0 { ^ CLAIM_GONE } {}
            : i xmax ( th_xmax tup )
            ? == xmax . x xid { ^ CLAIM_MINE } {}
            : i st0 ? == xmax 0 XS_ABORTED ( clog_get tm xmax )
            ? == st0 XS_ABORTED {
                ( heap_set_x st pw ( tid_slot tid ) . x xid . x cid 0 )
                ^ CLAIM_OK
            } {}
            ? == st0 XS_COMMITTED {
                // Gone before this snapshot: not there for it at all.
                ? ( snap_committed tm snap xmax ) { ^ CLAIM_GONE } {}
                ( abort_serialization )
            } {}
            = holder xmax
        }
        // Running: wait for it to end, holding no latch, then look again.
        ? ! ( txn_wait_for tm . x xid holder ) { ( abort_deadlock ) } {}
    }
}

@ tbl_delete Store st TxnMgr tm TxnCtx x Snapshot snap Table t i tid → b {
    ^ == ( tbl_claim st tm x snap tid ) CLAIM_OK
}

// Replace the row at `tid` with `row`: the old version claimed, a new one
// inserted. CLAIM_MINE (this statement already replaced it — reached again
// through an index, say) and CLAIM_GONE leave it be: -1.
@ tbl_update Store st TxnMgr tm TxnCtx x Snapshot snap Table t i tid ( Vec Value ) row → i {
    ? != ( tbl_claim st tm x snap tid ) CLAIM_OK { ^ -1 } {}
    ^ ( tbl_insert st t x row )
}
