// fire_and_forget_fiber_joined: `( fiber_join f )` on a handle from plain `spawn`, after the fiber
// ended: the runtime frees a fire-and-forget fiber's control block when
// its body returns, and the join read the freed block to see whether it
// was joinable.
// Closed: a handle from spawn / spawn_owned / fiber_current is not
// joinable, and fiber_join on one never touches the runtime (agora #168).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §3.3d | B | runs-clean | h613 | fiber_join on a plain spawn's handle after the fiber ended read its freed block; a non-joinable handle never touches the runtime (agora #168).
$ `stdlib/std/async.nu`

: ~ i g_n 0

@ main → i {
    ( runtime_init 1 )
    : Fiber f ( spawn \ → v { = g_n + g_n 1 } )
    ( runtime_run )
    ( fiber_join f )
    ( nurl_println_int g_n )
    ^ 0
}
