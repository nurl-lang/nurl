// fiber_handle_copy_joined_twice: `: Fiber b a`, then `( fiber_join a ) ( fiber_join b )`: two copies
// of one handle, each joined once, freed the control block twice.
// Closed: Fiber is move-only (its own drop), so `b` takes the handle and
// joining `a` is a use after move (agora #168).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.1 | A2 | rejected | h611 | as h610 through a copy `: Fiber b a`, each copy joined once (agora #168).
$ `stdlib/std/async.nu`

: ~ i g_n 0

@ main → i {
    ( runtime_init 1 )
    : Fiber a ( spawn_joinable \ → v { = g_n + g_n 1 } )
    : Fiber b a
    ( fiber_join a )
    ( fiber_join b )
    ^ 0
}
