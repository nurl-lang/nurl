// element_grown_inline_in_a_closure_handed_to_a_runner_past_a_view_of_it: agora #349 — `( run \ → v { ( vec_reserve ( vec_at vv 0 ) n ) } )` while a slice of the element is kept
// Closed: the closure's effect is marked lent on the captures its source expression names, and replays where the closure runs (agora #349).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #349: an element grown inline in a closure handed to a runner, past a view of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ run ( @ v ) f → v {
    ( f )
}

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    ( run \ → v { ( vec_reserve [u] ( vec_at [( Vec u )] vv 0 ) 4096 ) } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
