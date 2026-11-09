// element_grown_inline_in_a_closure_that_runs_past_a_view_of_it: agora #349 — `\ → v { ( vec_reserve [u] ( vec_at vv 0 ) 4096 ) }` run while a slice of `vv`'s element is kept
// Closed: the closure's effect is marked lent on the captures its source expression names, and replays where the closure runs (agora #349).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #349: an element grown inline in a closure that runs past a view of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    : ( @ v ) g \ → v { ( vec_reserve [u] ( vec_at [( Vec u )] vv 0 ) 4096 ) }
    ( g )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
