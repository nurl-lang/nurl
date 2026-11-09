// function_grows_an_element_of_an_element_of_its_parameter: agora #461 — a callee growing `( vec_at ( vec_at w 0 ) 0 )` of its parameter; the caller keeps a slice of it
// Closed: a function's drop and irealloc summaries follow a lend its names miss, by edges conditioned on the source expression and decided at module end (agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function grows an element of an element of its parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow ( Vec ( Vec ( Vec u ) ) ) w → v {
    ( vec_reserve [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) 4096 )
}

@ main → i {
    : ( Vec ( Vec ( Vec u ) ) ) w ( vec_new [( Vec ( Vec u ) )] )
    ( vec_push [( Vec ( Vec u ) )] w ( vec_new [( Vec u )] ) )
    ( vec_push [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) )
    ( grow w )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
