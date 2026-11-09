// function_binds_a_lender_handed_a_nested_lend_beside_a_parameter_and_grows_it: agora #461 — in `top`, `: r ( either ( vec_at p 0 ) q k )`, then `( vec_reserve r n )`
// Closed: a local bound to a lender handed a nested lend beside a named one is read out of both (agora #461).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function binds a lender handed a nested lend beside a parameter and grows it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ either ( Vec u ) a ( Vec u ) b i k → ( Vec u ) {
    ^ ? > k 0 a b
}

@ top ( Vec ( Vec u ) ) p ( Vec u ) q i k → v {
    : ( Vec u ) r ( either ( vec_at [( Vec u )] p 0 ) q k )
    ( vec_reserve [u] r 4096 )
}

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] w ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] w 0 ) 7 )
    : ( Vec u ) q0 ( vec_new [u] )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( top w q0 1 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
