// element_of_an_element_grown_in_a_closure_handed_to_a_runner_past_a_slice: agora #349 — a closure literal handed to a runner grows `( vec_at ( vec_at w 0 ) 0 )` while a slice of it is kept
// Closed: the closure's effect is marked lent on the captures its source expression names, and replays where the closure runs (agora #349).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #349: an element of an element grown in a closure handed to a runner past a slice
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ run ( @ v ) f → v {
    ( f )
}

@ main → i {
    : ( Vec ( Vec ( Vec u ) ) ) w ( vec_new [( Vec ( Vec u ) )] )
    ( vec_push [( Vec ( Vec u ) )] w ( vec_new [( Vec u )] ) )
    ( vec_push [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) )
    ( run \ → v { ( vec_reserve [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) 4096 ) } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
