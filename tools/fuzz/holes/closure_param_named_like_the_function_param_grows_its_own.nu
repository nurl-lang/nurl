// closure_param_named_like_the_function_param_grows_its_own: a closure literal whose parameter has the name of the enclosing function's (`vv`) grows that parameter's element: its growth was noted for the function's `vv` too, so the caller's slice of what it passed the function was ended — a safe program refused (agora #801).
// Closed: in __irealloc_edge_note / __irealloc_edge_note_c a name that is one of the literal's own parameters is the literal's only — it shadows the enclosing function's, which the body cannot reach.
// main (before this PR): refused ("'sl' borrows from 'w', which ended … passed to 'top', which may move the buffer of one of its elements").
// map: §7.6 | A2 | runs-clean | - | agora #801: a closure literal's parameter named like the function's parameter, its element grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ top ( Vec ( Vec u ) ) vv → i {
    : ( @ v ( Vec ( Vec u ) ) ) g \ ( Vec ( Vec u ) ) vv → v { ( vec_reserve [u] ( vec_at [( Vec u )] vv 0 ) 4096 ) }
    : ( Vec ( Vec u ) ) mine ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] mine ( vec_new [u] ) )
    ( g mine )
    ^ # i ( vec_len [( Vec u )] vv )
}

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    ( vec_push [( Vec u )] w inner )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( nurl_println_int ( top w ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
