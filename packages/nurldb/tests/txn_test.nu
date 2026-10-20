// txn_test.nu — transactions: the clog, snapshots, visibility, locks.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/txn_test.nu /tmp/tt && /tmp/tt
//
// Ids and the clog; what a snapshot sees of versions made by its own
// transaction (by command), by one that committed before it, by one still
// running, by one that committed after it was taken, and by one that
// aborted; a deleted version's visibility the same ways. Then the lock
// manager under threads: two threads take two locks in opposite orders
// 300 times — every round one of them is refused (deadlock) and the other
// gets both — and a transaction waits for another to finish.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`
$ `src/wal.nu`
$ `src/heap.nu`
$ `src/txn.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ check s what b ok → v {
    ? ok { = g_pass + g_pass 1 ( nurl_print `  ok ` ) } { = g_fail + g_fail 1 ( nurl_print `  FAIL ` ) }
    ( nurl_println what )
}

@ version i xmin i cmin i xmax i cmax → ( Vec u ) {
    : ( Vec Value ) row ( vec_new [Value] )
    ( vec_push [Value] row @ Value { VInt 7 } )
    : ( Vec u ) t ( tuple_build xmin cmin row )
    : ( Slice u ) ts ( slice_from_vec [u] t )
    ( slice_put_u64_le ts TH_XMAX xmax )
    ( slice_put_u32_le ts TH_CMAX cmax )
    ^ t
}

@ sees TxnMgr m Snapshot s ( Vec u ) t → b { ^ ( tuple_visible m s ( slice_from_vec [u] t ) ) }

@ main → i {
    : s lpath `/tmp/nurldb_txn_test.log`
    ?? ( file_delete lpath ) { T _ → {} F _ → {} }
    : Wal w ?? ( wal_open lpath F ) { T x → x F _ → { ^ 1 } }
    : TxnMgr m ( txnmgr_new 2 ( vec_new [u] ) )

    : i a ( txn_begin m )
    : i b ( txn_begin m )
    ( check `ids are handed out in order` & == a 2 == b 3 )
    ( txn_commit m w a )
    ( check `a commit is in the clog` == ( clog_get m a ) XS_COMMITTED )
    : i c ( txn_begin m )
    : i me ( txn_begin m )
    : Snapshot s ( txn_snapshot m me 2 )
    : i d ( txn_begin m )
    ( txn_commit m w c )
    ( txn_commit m w d )
    : i e ( txn_begin m )
    ( txn_abort m w e )
    ( check `an abort is in the clog` == ( clog_get m e ) XS_ABORTED )

    ( check `sees a version committed before it` ( sees m s ( version a 0 0 0 ) ) )
    ( check `not one still running when it began (b)` ! ( sees m s ( version b 0 0 0 ) ) )
    ( check `not one running then, committed since (c)` ! ( sees m s ( version c 0 0 0 ) ) )
    ( check `not one that began after it (d)` ! ( sees m s ( version d 0 0 0 ) ) )
    ( check `not one that aborted` ! ( sees m s ( version e 0 0 0 ) ) )
    ( check `its own version from an earlier command` ( sees m s ( version me 1 0 0 ) ) )
    ( check `not its own from this command (Halloween)` ! ( sees m s ( version me 2 0 0 ) ) )
    ( check `not a version deleted before it began` ! ( sees m s ( version XID_BOOT 0 a 0 ) ) )
    ( check `one deleted by a later commit still shows` ( sees m s ( version XID_BOOT 0 d 0 ) ) )
    ( check `one deleted by an abort still shows` ( sees m s ( version XID_BOOT 0 e 0 ) ) )
    ( check `not one it deleted in an earlier command` ! ( sees m s ( version XID_BOOT 0 me 1 ) ) )
    ( check `one it deletes in this command still shows` ( sees m s ( version XID_BOOT 0 me 2 ) ) )
    ( txn_commit m w b )
    ( txn_commit m w me )

    // Deadlocks: opposite orders, two threads, 300 rounds.
    : Atomic refused ( atomic_new 0 )
    : Atomic both ( atomic_new 0 )
    : ~ i round 0
    ~ < round 300 {
        : ( Vec Thread ) ts ( vec_new [Thread] )
        : ~ i t 0
        ~ < t 2 {
            : i me2 t
            : !Thread ThreadErr r ( thread_spawn \ → v {
                : i x ( txn_begin m )
                : i first ? == me2 0 1000 1001
                : i second ? == me2 0 1001 1000
                ? ( lock_acquire m x first LK_X ) {
                    ( sleep_ms 1 )
                    ? ( lock_acquire m x second LK_X ) { ( atomic_add both 1 ) } { ( atomic_add refused 1 ) }
                } { ( atomic_add refused 1 ) }
                ( txn_commit m w x )
            } )
            ?? r { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
            = t + t 1
        }
        ~ th ts { ( thread_join th ) }
        = round + round 1
    }
    ( check `every round finished (no thread hung)` == + ( atomic_load refused ) ( atomic_load both ) 600 )
    ( check `whenever both collided, one was refused` >= ( atomic_load both ) 300 )
    ( nurl_print `  (deadlocks detected: ` ) ( nurl_print_int ( txn_deadlocks m ) ) ( nurl_println `)` )

    // Waiting for another transaction to end.
    : i holder ( txn_begin m )
    : Atomic done ( atomic_new 0 )
    : !Thread ThreadErr wr ( thread_spawn \ → v {
        : i waiter ( txn_begin m )
        : b ok ( txn_wait_for m waiter holder )
        ? & ok == ( clog_get m holder ) XS_COMMITTED { ( atomic_store done 1 ) } { ( atomic_store done 2 ) }
        ( txn_commit m w waiter )
    } )
    ( sleep_ms 20 )
    ( check `the waiter waits while the other runs` == ( atomic_load done ) 0 )
    ( txn_commit m w holder )
    ?? wr { T th → { ( thread_join th ) } F _ → {} }
    ( check `and goes on once it has committed` == ( atomic_load done ) 1 )

    ( wal_close w )
    ?? ( file_delete lpath ) { T _ → {} F _ → {} }
    ( nurl_print `txn_test: ` ) ( nurl_print_int g_pass ) ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_println ` failed` )
    ^ ? == g_fail 0 0 1
}
