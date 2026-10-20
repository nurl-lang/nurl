// rwlock_relock_panics.nu — a thread taking an RwLocked it already holds
// for writing panics instead of going on as if it had the lock.
//
// pthreads answers the second request with EDEADLK rather than waiting
// for itself; the runtime ignored the answer, so the caller went on, its
// guard released the lock once and the first guard released it again — a
// lock in a broken state, and a database that hung on its next page
// latch. Now it is a panic: recover gets the reason, and the unwind drops
// the guard the thread did hold, so the lock can be taken again. (The
// calls that take a lock count as calls that may panic, so the guard's
// journal registration is kept.)

$ `stdlib/std/rwlock.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

@ twice ( RwLocked i ) l → i {
    : ( WGuard i ) w ( rw_write [i] l )
    : ( RGuard i ) r ( rw_read [i] l )
    ^ 1
}

@ main → i {
    : ( RwLocked i ) l ( rw_new [i] 5 )
    : !v PanicInfo p ( recover \ → v { : i _x ( twice l ) } )
    ?? p { T _ → { ( nurl_println `no panic` ) } F e → { ( nurl_println ( string_data . e msg ) ) ( panic_info_free e ) } }
    // The unwind let go of the write lock: it can be taken again.
    : ( WGuard i ) w2 ( rw_write [i] l )
    ( nurl_println `taken again` )
    ^ 0
}
