// fiber_joins_its_own_current_handle: a joinable fiber that joins the handle fiber_current gave it: it
// waited for its own end, which never came, and the program hung; a join
// that did return would have freed the running fiber's block.
// Closed: fiber_current's handle is not joinable, so the join is a no-op,
// and dropping it does nothing (agora #168).
// v0.80.0: accepted; hung in nurl_fiber_join.
// map: §3.3d | B | runs-clean | h614 | a joinable fiber joined fiber_current's handle and waited for its own end (hang); fiber_current's handle is not joinable (agora #168).
$ `stdlib/std/async.nu`

: ~ i g_n 0

@ main → i {
    ( runtime_init 1 )
    : Fiber f ( spawn_joinable \ → v {
        ?? ( fiber_current ) { T me → ( fiber_join me ) F → {} }
        = g_n + g_n 1
    } )
    ( fiber_join f )
    ( nurl_println_int g_n )
    ^ 0
}
