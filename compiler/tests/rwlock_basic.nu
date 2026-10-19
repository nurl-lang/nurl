// rwlock_basic.nu — std/rwlock.nu acceptance.
//
// One thread: a read guard lends the value, a write guard changes it
// (through a slice of its Vec, and in place with wguard_update), the try
// variants refuse while the other kind is held and succeed once it goes,
// rw_get copies and rw_set replaces. Then four writer threads and four
// reader threads share one page of 64 counters: a writer bumps every
// counter under one write guard, so a reader holding a read guard must
// see all 64 equal — any torn page is counted — and the final value is
// exactly the number of writes. Hand-over-hand: a reader takes the next
// page's guard before letting the previous one go. A panic while guards
// are held releases them on the way to recover.

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/rwlock.nu`
$ `stdlib/std/panic.nu`

: Page { ( Vec i ) cells i version }

@ page_new i n → Page { ^ @ Page { ( vec_zeroed [i] n ) 0 } }

@ show s label i x → v { ( nurl_print label ) ( nurl_println_int x ) }

// Every counter equal to the first: one read guard's consistent view.
@ page_even ( RwLocked Page ) l → b {
    : ( RGuard Page ) g ( rw_read [Page] l )
    : ( Slice i ) c ( slice_from_vec [i] . ( rguard_get [Page] g ) cells )
    : i first ( slice_at [i] c 0 )
    : ~ i k 1
    ~ < k ( slice_len [i] c ) {
        ? != ( slice_at [i] c k ) first { ^ F } {}
        = k + k 1
    }
    ^ T
}

@ page_bump ( RwLocked Page ) l → v {
    : ( WGuard Page ) g ( rw_write [Page] l )
    : ( Slice i ) c ( slice_from_vec [i] . ( wguard_get [Page] g ) cells )
    : ~ i k 0
    ~ < k ( slice_len [i] c ) {
        ( slice_put [i] c k + ( slice_at [i] c k ) 1 )
        = k + k 1
    }
    ( wguard_update [Page] g \ inout Page p → v { = . p version + . p version 1 } )
}

@ main → i {
    : ( RwLocked Page ) l ( rw_new [Page] ( page_new 8 ) )
    : ( RwLocked Page ) a0 ( rw_new [Page] ( page_new 2 ) )
    ( page_bump l )
    ( page_bump l )
    {
        : ( RGuard Page ) r ( rw_read [Page] l )
        : Page p ( rguard_get [Page] r )
        ( show `cell 3:    ` ( vec_at [i] . p cells 3 ) )
        ( show `version:   ` . p version )
        // A second reader at the same time is fine; a writer is not.
        ?? ( rw_try_read [Page] l ) { T _ → { ( show `2nd read:  ` 1 ) } F → { ( show `2nd read:  ` 0 ) } }
        ?? ( rw_try_write [Page] l ) { T _ → { ( show `try write: ` 1 ) } F → { ( show `try write: ` 0 ) } }
    }
    ?? ( rw_try_write [Page] l ) { T _ → { ( show `free write:` 1 ) } F → { ( show `free write:` 0 ) } }
    {
        : ( WGuard Page ) w ( rw_write [Page] l )
        ?? ( rw_try_read [Page] l ) { T _ → { ( show `read in w: ` 1 ) } F → { ( show `read in w: ` 0 ) } }
    }
    : Page copy ( rw_get [Page] l )
    ( rw_set [Page] l ( page_new 4 ) )
    ( show `copy len:  ` ( vec_len [i] . copy cells ) )
    ( show `new len:   ` ( vec_len [i] . ( rw_get [Page] l ) cells ) )
    ( rw_update [Page] l \ inout Page p → v { = . p version 41 } )
    ( show `updated:   ` ( rw_apply [Page i] l \ inout Page p → i { = . p version + . p version 1 ^ . p version } ) )

    // A panic while a guard is held: the drop journal runs the guard's
    // drop on the way to recover, so the lock is free again after it.
    : !v PanicInfo pr ( recover \ → v {
        : ( WGuard Page ) w ( rw_write [Page] l )
        : ( RGuard Page ) other ( rw_read [Page] a0 )
        ( panic `inside the guards` )
    } )
    ?? pr { T _ → { ( show `panicked:  ` 0 ) } F _ → { ( show `panicked:  ` 1 ) } }
    ?? ( rw_try_write [Page] l ) { T _ → { ( show `freed w:   ` 1 ) } F → { ( show `freed w:   ` 0 ) } }
    ?? ( rw_try_write [Page] a0 ) { T _ → { ( show `freed r:   ` 1 ) } F → { ( show `freed r:   ` 0 ) } }

    // Four writers, four readers, two pages.
    : ( RwLocked Page ) a ( rw_new [Page] ( page_new 64 ) )
    : ( RwLocked Page ) b ( rw_new [Page] ( page_new 64 ) )
    : Atomic torn ( atomic_new 0 )
    : Atomic reads ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 4 {
        : !Thread ThreadErr wr ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 2000 { ( page_bump a ) ( page_bump b ) = k + k 1 }
        } )
        ?? wr { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        : !Thread ThreadErr rd ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 2000 {
                ? ! ( page_even a ) { ( atomic_add torn 1 ) } {}
                // Hand over hand: b's guard is taken before a's goes.
                : ( RGuard Page ) ga ( rw_read [Page] a )
                : ( RGuard Page ) gb ( rw_read [Page] b )
                : Page pa ( rguard_get [Page] ga )
                : Page pb ( rguard_get [Page] gb )
                ? > . pa version -1 { ( atomic_add reads 1 ) } {}
                ? ! ( page_even b ) { ( atomic_add torn 1 ) } {}
                = k + k 1
            }
        } )
        ?? rd { T th → { ( vec_push [Thread] ts th ) } F _ → {} }
        = t + t 1
    }
    ~ th ts { ( thread_join th ) }
    ( show `torn pages: ` ( atomic_load torn ) )
    ( show `reads:      ` ( atomic_load reads ) )
    ( show `a cell 63:  ` ( vec_at [i] . ( rw_get [Page] a ) cells 63 ) )
    ( show `b version:  ` . ( rw_get [Page] b ) version )
    ^ 0
}
