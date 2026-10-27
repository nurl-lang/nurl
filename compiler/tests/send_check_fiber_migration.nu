// send_check_fiber_migration.nu — the thread crossing's check (agora #121)
// run by fibers that yield on four workers between their crossings. The
// check counts into a per-thread table; inlined into a fiber's function,
// the table's address was taken once at its entry, so a fiber that had
// moved to another worker since counted into that worker's table, and a
// crossing another fiber was walking there met an entry it never made — a
// freed block's address read as an owner count, a false panic (the HTTP
// server's accept loop, under h2spec). The runtime keeps those entries out
// of line (NURL_TLS_FN). Every crossing here has its only owner: none may
// panic.
// requires: fibers

$ `stdlib/dist/crdt.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/atomic.nu`

@ hop i k Atomic done → v {
    : ~ i j 0
    ~ < j 50 {
        ( yield )
        : PNCounter a ( pncounter_new )
        ( pncounter_inc a k 1 )
        : Fiber f ( spawn_owned \ → v { ( pncounter_inc a + k 1 1 ) : i _n ( atomic_add done 1 ) } )
        ( yield )
        = j + j 1
    }
}

unsafe @ main → i {
    ( runtime_init 4 )
    : Atomic done ( atomic_new 0 )
    : ~ i k 1
    ~ <= k 200 { : i kk k : Fiber f ( spawn_owned \ → v { ( hop kk done ) } ) = k + k 1 }
    ( runtime_run )
    ( runtime_shutdown )
    ( nurl_println ( nurl_str_cat `crossed ` ( nurl_str_int ( atomic_load done ) ) ) )
    ^ 0
}
