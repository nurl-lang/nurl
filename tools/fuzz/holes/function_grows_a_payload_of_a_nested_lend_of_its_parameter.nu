// function_grows_a_payload_of_a_nested_lend_of_its_parameter: agora #461 — `top` grows the `??` payload of `( vec_get ( vec_at w 0 ) 0 )`; the caller keeps a slice across the call
// Closed: a function's drop and irealloc summaries follow a lend its names miss, by edges conditioned on the source expression and decided at module end (agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function grows a payload of a nested lend of its parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ top ( Vec ( Vec ( Vec u ) ) ) w → v {
    ?? ( vec_get [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) { T e → { ( vec_reserve [u] e 4096 ) } F → {} }
}

@ main → i {
    : ( Vec ( Vec ( Vec u ) ) ) w ( vec_new [( Vec ( Vec u ) )] )
    ( vec_push [( Vec ( Vec u ) )] w ( vec_new [( Vec u )] ) )
    ( vec_push [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) )
    ( top w )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
