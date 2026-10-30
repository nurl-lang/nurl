// fiber_joined_twice: `( fiber_join f ) ( fiber_join f )` on one spawn_joinable handle:
// the first join freed the fiber's control block and the second waited on
// its mutex and freed it again. Fiber was a plain copyable `{ s raw }`,
// and "join exactly once" was only a comment.
// Closed: Fiber is a sealed, move-only handle and fiber_join takes it
// (`sink`): the second join is a use after move (agora #168).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.1 | A2 | rejected | h610 | `( fiber_join f ) ( fiber_join f )` on one spawn_joinable handle: the second join freed the fiber's control block again (agora #168). Fiber is move-only and fiber_join takes it.
$ `stdlib/std/async.nu`

: ~ i g_n 0

@ main → i {
    ( runtime_init 1 )
    : Fiber f ( spawn_joinable \ → v { = g_n + g_n 1 } )
    ( fiber_join f )
    ( fiber_join f )
    ^ 0
}
