// racy_counter.nu — a deliberately racy test for `nurlpkg test --sim`
// (agora #261): two fibers each add one to a shared counter by reading
// it, yielding, and writing back what they read plus one. Whether an
// update is lost depends only on the order the scheduler runs them in —
// when both read before either writes, the count is 1 — so the bug
// shows under some seeds and not others, and the seed it showed under
// replays it exactly. tools/nurlpkg/test-sim.sh is the gate.

$ `stdlib/std/async.nu`
$ `stdlib/std/atomic.nu`

@ main → i {
    ( runtime_init 1 )
    : Atomic c ( atomic_new 0 )
    : Atomic ca ( Atomic_share c )
    : Atomic cb ( Atomic_share c )
    : ( @ v ) a \ → v {
        : i x ( atomic_load ca )
        ( yield )
        ( atomic_store ca + x 1 )
    }
    : ( @ v ) b \ → v {
        : i x ( atomic_load cb )
        ( yield )
        ( atomic_store cb + x 1 )
    }
    ( spawn a )
    ( spawn b )
    ( runtime_run )
    ( nurl_print `count=` )
    ( nurl_println_int ( atomic_load c ) )
    ^ 0
}
