// packages/nurldb/src/txn.nu — transactions: ids, the commit log,
// snapshots, visibility, and the lock manager.
//
// Multi-version concurrency control. A row's versions are tuples (heap.nu)
// stamped with the transaction that made each one (xmin) and the one that
// deleted or superseded it (xmax). A transaction reads through a
// SNAPSHOT: the set of transactions whose work it sees is fixed when the
// snapshot is taken — those that had committed by then — so readers never
// wait for writers and a query sees one consistent state of the database
// (snapshot isolation).
//
//   ( txn_begin m )                     → Txn
//   ( txn_snapshot m x cid )            → Snapshot
//   ( tuple_visible m s tuple )         → b
//   ( txn_commit m wal x )              → v    durable before it returns
//   ( txn_finish_readonly m x )         → v    one that wrote nothing
//   ( txn_abort m wal x )               → v
//
// The commit log (clog) holds each transaction's fate: 0 in progress,
// 1 committed, 2 aborted. A version made by an aborted transaction is
// invisible to everyone — rollback needs no undo.
//
// Ordering, which is the whole correctness argument:
//   * an id is handed out and entered in the active set under one lock,
//     the one a snapshot is taken under, so no snapshot sees an id that
//     is neither active nor finished;
//   * a commit is durable in the log, THEN marked committed in the clog,
//     THEN removed from the active set: a snapshot taken before the
//     removal lists it as active (invisible to that snapshot for good), one
//     taken after finds it committed — no snapshot sees a transaction's
//     work come and go.
//
// Write-write conflicts: a transaction that updates or deletes a version
// another one has claimed (xmax set by a transaction still running) waits
// for that one to finish — by asking the lock manager for the other
// transaction's id, which its owner holds exclusively until it ends. Every
// wait first checks the waits-for graph: a wait that would close a cycle
// is refused and its transaction aborted (deadlock).

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/panic.nu`
$ `wal.nu`
$ `logrec.nu`
$ `heap.nu`

: i XS_RUNNING 0
: i XS_COMMITTED 1
: i XS_ABORTED 2

// The id of the bootstrap transaction: committed before anything began
// (what the catalog's first rows are stamped with).
: i XID_BOOT 1

: i LK_S 1
: i LK_X 2

: Snapshot {
    i xid  // the reader's own transaction
    i cid  // its current command: its own changes from this one on are unseen
    i xmin  // every id below it had finished when the snapshot was taken
    i xmax  // every id from it on had not begun
    ( Vec i ) active  // ids in [xmin, xmax) still running then
}

: TxnState {
    i next
    ( Vec i ) active
}

: LockEntry {
    i res
    i txn
    i mode
    b granted
}

: LockTable { ( Vec LockEntry ) entries }

: TxnMgrImpl {
    ( Locked TxnState ) state
    ( RwLocked ( Vec u ) ) clog
    ( Locked LockTable ) locks
    // Commits / aborts / deadlocks so far (statistics).
    Atomic commits
    Atomic aborts
    Atomic deadlocks
}

: TxnMgr { ( Arc TxnMgrImpl ) a }

@ TxnMgr_share TxnMgr m → TxnMgr { ^ @ TxnMgr { ( arc_clone [TxnMgrImpl] . m a ) } }

@ TxnMgr_drop sink TxnMgr m → v {}

// A manager whose next id is `next` and whose clog is `clog` (both from
// recovery; a fresh database starts at 2 with an empty clog).
@ txnmgr_new i next ( Vec u ) clog → TxnMgr {
    : ( Vec u ) c clog
    ? < ( vec_len [u] c ) + XID_BOOT 1 { : b _r ( vec_resize_zeroed [u] c + XID_BOOT 1 ) } {}
    ( vec_put [u] c XID_BOOT # u XS_COMMITTED )
    ^ @ TxnMgr { ( arc_new [TxnMgrImpl] @ TxnMgrImpl {
            ( locked_new [TxnState] @ TxnState { next ( vec_new [i] ) } )
            ( rw_new [( Vec u )] c )
            ( locked_new [LockTable] @ LockTable { ( vec_new [LockEntry] ) } )
            ( atomic_new 0 ) ( atomic_new 0 ) ( atomic_new 0 )
        } ) }
}

@ txn_commits TxnMgr m → i { ^ ( atomic_load . ( arc_get [TxnMgrImpl] . m a ) commits ) }

@ txn_aborts TxnMgr m → i { ^ ( atomic_load . ( arc_get [TxnMgrImpl] . m a ) aborts ) }

@ txn_deadlocks TxnMgr m → i { ^ ( atomic_load . ( arc_get [TxnMgrImpl] . m a ) deadlocks ) }

@ txn_next_xid TxnMgr m → i {
    ^ ( locked_apply [TxnState i] . ( arc_get [TxnMgrImpl] . m a ) state \ inout TxnState s → i { ^ . s next } )
}

// ── the commit log ─────────────────────────────────────────────────────

@ clog_get TxnMgr m i xid → i {
    : ( RGuard ( Vec u ) ) g ( rw_read [( Vec u )] . ( arc_get [TxnMgrImpl] . m a ) clog )
    : ( Vec u ) c ( rguard_get [( Vec u )] g )
    ? >= xid ( vec_len [u] c ) { ^ XS_RUNNING } {}
    ^ # i ( vec_at [u] c xid )
}

@ clog_set TxnMgr m i xid i st → v {
    : ( WGuard ( Vec u ) ) g ( rw_write [( Vec u )] . ( arc_get [TxnMgrImpl] . m a ) clog )
    : ( Vec u ) c ( wguard_get [( Vec u )] g )
    ? >= xid ( vec_len [u] c ) { : b _r ( vec_resize_zeroed [u] c + xid 4096 ) } {}
    ( vec_put [u] c xid # u st )
}

// A copy of the clog (for a checkpoint to write out).
@ clog_copy TxnMgr m → ( Vec u ) { ^ ( rw_get [( Vec u )] . ( arc_get [TxnMgrImpl] . m a ) clog ) }

// ── transactions ───────────────────────────────────────────────────────

// A new transaction: its id, entered in the active set, holding its own id
// exclusively in the lock manager (what a transaction waiting for it waits
// on).
@ txn_begin TxnMgr m → i {
    : TxnMgrImpl x ( arc_get [TxnMgrImpl] . m a )
    : i xid ( locked_apply [TxnState i] . x state \ inout TxnState s → i {
        : i id . s next
        = . s next + id 1
        ( vec_push [i] . s active id )
        ^ id
    } )
    : b _g ( lock_acquire m xid - 0 xid LK_X )
    ^ xid
}

// The snapshot `xid` reads through for its command `cid`.
@ txn_snapshot TxnMgr m i xid i cid → Snapshot {
    : TxnMgrImpl x ( arc_get [TxnMgrImpl] . m a )
    ^ ( locked_apply [TxnState Snapshot] . x state \ inout TxnState s → Snapshot {
        : ( Vec i ) act ( vec_clone [i] . s active )
        : ~ i lo . s next
        ~ a act { ? < a lo { = lo a } {} }
        ^ @ Snapshot { xid cid lo . s next act }
    } )
}

@ __active_remove TxnMgr m i xid → v {
    ( locked_update [TxnState] . ( arc_get [TxnMgrImpl] . m a ) state \ inout TxnState s → v {
        : i n ( vec_len [i] . s active )
        : ~ i k 0
        ~ < k n {
            ? == ( vec_at [i] . s active k ) xid {
                ( vec_put [i] . s active k ( vec_at [i] . s active - n 1 ) )
                : ?i _p ( vec_pop [i] . s active )
                ^
            } {}
            = k + k 1
        }
    } )
}

// Commit: the commit record durable, then the clog, then the active set
// (the order the header gives), then the transaction's locks released.
@ txn_commit TxnMgr m Wal w i xid → v {
    : ( Vec u ) r ( rec_new R_COMMIT 9 )
    ( rec_u64 r xid )
    ( wal_flush_to w ( wal_append w ( slice_from_vec [u] r ) ) )
    ( clog_set m xid XS_COMMITTED )
    ( __active_remove m xid )
    ( lock_release_all m xid )
    ( atomic_add . ( arc_get [TxnMgrImpl] . m a ) commits 1 )
}

// End a transaction that wrote nothing: there is nothing to make durable,
// and no version of its own for anyone to see, so no log record is needed
// (recovery calls it aborted, which says the same).
@ txn_finish_readonly TxnMgr m i xid → v {
    ( clog_set m xid XS_COMMITTED )
    ( __active_remove m xid )
    ( lock_release_all m xid )
}

// Abort: its versions become invisible the moment the clog says so; the
// abort record lets recovery say the same (and need not be durable: a
// transaction the log does not see commit is aborted by recovery anyway).
@ txn_abort TxnMgr m Wal w i xid → v {
    : ( Vec u ) r ( rec_new R_ABORT 9 )
    ( rec_u64 r xid )
    : i _l ( wal_append w ( slice_from_vec [u] r ) )
    ( clog_set m xid XS_ABORTED )
    ( __active_remove m xid )
    ( lock_release_all m xid )
    ( atomic_add . ( arc_get [TxnMgrImpl] . m a ) aborts 1 )
}

// ── visibility ─────────────────────────────────────────────────────────

@ __snap_active Snapshot s i x → b {
    : ( Vec i ) act . s active
    ~ a act { ? == a x { ^ T } {} }
    ^ F
}

// Did `x` commit before the snapshot was taken?
@ snap_committed TxnMgr m Snapshot s i x → b {
    ? == x XID_BOOT { ^ T } {}
    ? >= x . s xmax { ^ F } {}
    ? & >= x . s xmin ( __snap_active s x ) { ^ F } {}
    ^ == ( clog_get m x ) XS_COMMITTED
}

// Is the version `t` (a tuple's bytes) part of what snapshot `s` sees?
@ tuple_visible TxnMgr m Snapshot s ( Slice u ) t → b {
    : i xmin ( th_xmin t )
    ? == xmin . s xid {
        ? >= ( th_cmin t ) . s cid { ^ F } {}
    } {
        ? ! ( snap_committed m s xmin ) { ^ F } {}
    }
    : i xmax ( th_xmax t )
    ? == xmax 0 { ^ T } {}
    ? == xmax . s xid { ^ >= ( th_cmax t ) . s cid } {}
    ^ ! ( snap_committed m s xmax )
}

// ── the lock manager ───────────────────────────────────────────────────

@ __lk_compat i a i b → b { ^ & == a LK_S == b LK_S }

// The transactions `txn`'s waiting request on `res` (mode `mode`) waits
// for: holders it is incompatible with, and incompatible requests queued
// ahead of it.
@ __lk_blockers LockTable t i txn i res i mode → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : ( Vec LockEntry ) es . t entries
    ~ e es {
        ? & == . e res res != . e txn txn {
            ? ! ( __lk_compat . e mode mode ) { ( vec_push [i] out . e txn ) } {}
        } {}
    }
    ^ out
}

// What `txn` is waiting for (its one ungranted request), or -1 res.
@ __lk_waiting LockTable t i txn → LockEntry {
    : ( Vec LockEntry ) es . t entries
    ~ e es { ? & == . e txn txn ! . e granted { ^ @ LockEntry { . e res . e txn . e mode F } } {} }
    ^ @ LockEntry { 0 -1 0 F }
}

// Would `start` waiting close a cycle in the waits-for graph?
@ __lk_cycle LockTable t i start → b {
    : ( Vec i ) seen ( vec_new [i] )
    : ( Vec i ) todo ( vec_new [i] )
    ( vec_push [i] todo start )
    ~ > ( vec_len [i] todo ) 0 {
        : i cur ?? ( vec_pop [i] todo ) { T c → c F → -1 }
        : LockEntry w ( __lk_waiting t cur )
        ? >= . w txn 0 {
            : ( Vec i ) bl ( __lk_blockers t cur . w res . w mode )
            ~ who bl {
                ? == who start { ^ T } {}
                : ~ b known F
                ~ sn seen { ? == sn who { = known T } {} }
                ? ! known { ( vec_push [i] seen who ) ( vec_push [i] todo who ) } {}
            }
        } {}
    }
    ^ F
}

// Can `txn`'s request at index `k` be granted now?
@ __lk_grantable LockTable t i k → b {
    : LockEntry me ( vec_at [LockEntry] . t entries k )
    : ~ i j 0
    ~ < j ( vec_len [LockEntry] . t entries ) {
        : LockEntry e ( vec_at [LockEntry] . t entries j )
        ? & == . e res . me res != . e txn . me txn {
            // a holder, or a waiter queued ahead (first come, first served)
            ? | . e granted < j k {
                ? ! ( __lk_compat . e mode . me mode ) { ^ F } {}
            } {}
        } {}
        = j + j 1
    }
    ^ T
}

// Take `res` in `mode` for `txn`, waiting while another transaction holds
// it in a mode that conflicts. F: the wait would deadlock — the request is
// withdrawn, and the caller aborts its transaction.
@ lock_acquire TxnMgr m i txn i res i mode → b {
    : TxnMgrImpl x ( arc_get [TxnMgrImpl] . m a )
    : i got ( locked_await [LockTable i] . x locks \ inout LockTable t → ?i {
        : i n ( vec_len [LockEntry] . t entries )
        : ~ i mine -1
        : ~ i k 0
        ~ < k n {
            : LockEntry e ( vec_at [LockEntry] . t entries k )
            ? & == . e res res == . e txn txn {
                // Already held as strongly: nothing to do.
                ? & . e granted >= . e mode mode { ^ @ ?i { T 1 } } {}
                ? ! . e granted { = mine k } {}
            } {}
            = k + k 1
        }
        ? < mine 0 {
            ( vec_push [LockEntry] . t entries @ LockEntry { res txn mode F } )
            = mine n
            ? ( __lk_cycle t txn ) {
                : ?LockEntry _w ( vec_pop [LockEntry] . t entries )
                ^ @ ?i { T 0 }
            } {}
        } {}
        ? ( __lk_grantable t mine ) {
            : LockEntry e ( vec_at [LockEntry] . t entries mine )
            ( vec_put [LockEntry] . t entries mine @ LockEntry { . e res . e txn . e mode T } )
            ^ @ ?i { T 1 }
        } {}
        ^ @ ?i { F 0 }
    } )
    ? == got 0 { ( atomic_add . x deadlocks 1 ) ^ F } {}
    ^ T
}

// Release every lock `txn` holds or waits for (at its end).
@ lock_release_all TxnMgr m i txn → v {
    ( locked_update [LockTable] . ( arc_get [TxnMgrImpl] . m a ) locks \ inout LockTable t → v {
        ( vec_retain [LockEntry] . t entries \ LockEntry e → b { ^ != . e txn txn } )
    } )
}

// Wait until transaction `other` has finished (committed or aborted): ask
// for its id in shared mode — it holds it exclusively until it ends — and
// let go at once. F: the wait would deadlock.
@ txn_wait_for TxnMgr m i me i other → b {
    ? ! ( lock_acquire m me - 0 other LK_S ) { ^ F } {}
    ( locked_update [LockTable] . ( arc_get [TxnMgrImpl] . m a ) locks \ inout LockTable t → v {
        ( vec_retain [LockEntry] . t entries \ LockEntry e → b { ^ | != . e txn me != . e res - 0 other } )
    } )
    ^ T
}
