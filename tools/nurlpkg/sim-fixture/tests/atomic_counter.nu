// atomic_counter.nu — racy_counter.nu done right: each fiber adds one
// with a single atomic read-modify-write, across the same yield, so no
// schedule loses an update and every seed passes (agora #261).

$ `stdlib/std/async.nu`
$ `stdlib/std/atomic.nu`

@ main → i {
    ( runtime_init 1 )
    : Atomic c ( atomic_new 0 )
    : Atomic ca ( Atomic_share c )
    : Atomic cb ( Atomic_share c )
    : ( @ v ) a \ → v {
        ( yield )
        : i _a ( atomic_add ca 1 )
    }
    : ( @ v ) b \ → v {
        ( yield )
        : i _b ( atomic_add cb 1 )
    }
    ( spawn a )
    ( spawn b )
    ( runtime_run )
    ( nurl_print `count=` )
    ( nurl_println_int ( atomic_load c ) )
    ^ 0
}
