// closure_body_local_bound_to_a_value_block_grown_past_a_slice: agora #349 — inside a closure handed to a runner, a body local bound to a value block of a lend, then grown; a slice of the element kept
// Closed: a closure body local read out of a lend no name carries reaches the captures its source expression names (agora #349, #449).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #349: a closure body local bound to a value block grown past a slice
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ run ( @ v ) f → v {
    ( f )
}

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    ( run \ → v { : ( Vec u ) j { : ( Vec u ) t ( vec_at [( Vec u )] vv 0 ) t } ( vec_reserve [u] j 4096 ) } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
