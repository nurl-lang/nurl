// rwlock_relock_panics.nu — taking an RwLocked its holder already has.
//
// For writing, or for reading and then for writing, the second request
// would wait for the holder itself: it panics instead. pthreads answers
// the first with EDEADLK on some systems (Linux) and waits on others
// (FreeBSD), and nothing answers the second; the runtime remembers each
// lock's writer and each holder's read locks, so every platform panics
// alike. recover gets the reason, and the unwind drops the guard the
// holder did have, so the lock can be taken again. (The calls that take
// a lock count as calls that may panic, so a guard's journal
// registration is kept.)
//
// A second read guard of a lock its holder already reads is counted, not
// taken again: taken again, it waited behind a writer that was waiting
// for the first one (an SRWLOCK and FreeBSD's and macOS's rwlocks let a
// waiting writer go first) — the last case: a writer is queued while the
// main thread holds a read guard, and the main thread takes another.
// requires: live

$ `stdlib/std/rwlock.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`

@ twice ( RwLocked i ) l → i {
    : ( WGuard i ) w ( rw_write [i] l )
    : ( RGuard i ) r ( rw_read [i] l )
    ^ 1
}

@ upgrade ( RwLocked i ) l → i {
    : ( RGuard i ) r ( rw_read [i] l )
    : ( WGuard i ) w ( rw_write [i] l )
    ^ 2
}

@ main → i {
    : ( RwLocked i ) l ( rw_new [i] 5 )
    : !v PanicInfo p ( recover \ → v { : i _x ( twice l ) } )
    ?? p { T _ → { ( nurl_println `no panic` ) } F e → { ( nurl_println ( string_data . e msg ) ) ( panic_info_free e ) } }
    : !v PanicInfo q ( recover \ → v { : i _y ( upgrade l ) } )
    ?? q { T _ → { ( nurl_println `no panic` ) } F e → { ( nurl_println ( string_data . e msg ) ) ( panic_info_free e ) } }
    // The unwinds let go of what was held: it can be taken again.
    {
        : ( WGuard i ) w2 ( rw_write [i] l )
        ( nurl_println `taken again` )
    }

    // A writer waits while this thread reads; this thread reads again.
    : Atomic wrote ( atomic_new 0 )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    {
        : ( RGuard i ) r1 ( rw_read [i] l )
        : !Thread ThreadErr t ( thread_spawn \ → v {
            : ( WGuard i ) w ( rw_write [i] l )
            ( atomic_store wrote 1 )
        } )
        ?? t { T h → { ( vec_push [Thread] ts h ) } F _ → {} }
        ( sleep_ms 100 )
        {
            : ( RGuard i ) r2 ( rw_read [i] l )
            ( nurl_println ( nurl_str_cat `read again while a writer waits: ` ( nurl_str_int ( rguard_get [i] r2 ) ) ) )
        }
        ( nurl_println ( nurl_str_cat `the writer still waits: ` ( nurl_str_int - 1 ( atomic_load wrote ) ) ) )
    }
    ~ h ts { ( thread_join h ) }
    ( nurl_println ( nurl_str_cat `then it writes: ` ( nurl_str_int ( atomic_load wrote ) ) ) )
    ^ 0
}
