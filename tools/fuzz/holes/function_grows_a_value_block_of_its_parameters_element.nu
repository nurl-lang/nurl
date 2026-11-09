// function_grows_a_value_block_of_its_parameters_element: agora #461 — `top` grows `{ : t ( vec_at vv 0 ) t }` of its parameter; the caller keeps a slice across `( top vv )`
// Closed: a function's drop and irealloc summaries follow a lend its names miss, by edges conditioned on the source expression and decided at module end (agora #461).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function grows a value block of its parameter's element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ top ( Vec ( Vec u ) ) vv → v {
    ( vec_reserve [u] { : ( Vec u ) t ( vec_at [( Vec u )] vv 0 ) t } 4096 )
}

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    ( top vv )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
