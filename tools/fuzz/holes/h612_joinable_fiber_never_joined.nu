// H612: a spawn_joinable fiber whose handle is never joined: the runtime
// kept the finished fiber's control block for a join that never came, and
// it leaked with its stack.
// Closed: dropping a joinable handle detaches the fiber — the runtime
// frees its block when the body ends, or at once if it already has
// (nurl_fiber_detach; agora #168).
// v0.80.0: accepted; LeakSanitizer reported the block from
// nurl__fiber_alloc.
$ `stdlib/std/async.nu`

: ~ i g_n 0

@ start → v {
    : Fiber _f ( spawn_joinable \ → v { = g_n + g_n 1 } )
}

@ main → i {
    ( runtime_init 1 )
    ( start )
    ( runtime_run )
    ( nurl_println_int g_n )
    ^ 0
}
