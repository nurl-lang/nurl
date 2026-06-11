// cell_pthread.nu — direct libpthread FFI over Cell-allocated storage.
//
// Builds a Mutex primitive directly from `pthread_mutex_init` /
// `_lock` / `_unlock` / `_destroy` over a Cell-allocated buffer
// whose size comes from `nurl_native_sizeof("pthread_mutex_t")`.
// No C-side `nurl_mutex_*` helper involved.

$ `stdlib/core/cell.nu`

// Direct pthread FFI. `pthread_mutex_init`'s second arg is a
// `pthread_mutexattr_t *` (or NULL for defaults); we pass NULL.
& `c` @ pthread_mutex_init *u m *u attr → i

& `c` @ pthread_mutex_lock *u m → i

& `c` @ pthread_mutex_unlock *u m → i

& `c` @ pthread_mutex_destroy *u m → i

@ pure_mutex_new → Cell {
    : Cell c ( cell_for_native `pthread_mutex_t` )
    ? ( cell_is_null c ) { ^ c } {}
    ( pthread_mutex_init ( cell_ptr c ) # *u 0 )
    ^ c
}

@ pure_mutex_lock Cell c → v {
    ( pthread_mutex_lock ( cell_ptr c ) )
}

@ pure_mutex_unlock Cell c → v {
    ( pthread_mutex_unlock ( cell_ptr c ) )
}

@ pure_mutex_destroy Cell c → v {
    ( pthread_mutex_destroy ( cell_ptr c ) )
    ( cell_free c )
}

@ main → i {
    : Cell m ( pure_mutex_new )
    ( nurl_print `cell is_null=` ) ( nurl_print ? ( cell_is_null m ) `T` `F` )
    ( nurl_print ` size>0=` ) ( nurl_print ? > ( cell_size m ) 0 `T` `F` )
    ( nurl_print `\n` )

    // Lock / unlock round-trip — same thread, so this is a no-op
    // for correctness, but exercises the FFI plumbing.
    ( pure_mutex_lock m )
    ( nurl_print `locked\n` )
    ( pure_mutex_unlock m )
    ( nurl_print `unlocked\n` )

    // Lock again to confirm the mutex is in a healthy state after
    // one round-trip.
    ( pure_mutex_lock m )
    ( pure_mutex_unlock m )
    ( nurl_print `round-trip 2 ok\n` )

    ( pure_mutex_destroy m )
    ( nurl_print `done\n` )
    ^ 0
}
