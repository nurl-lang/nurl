// closure_growing_another_vecs_element_inline_runs_clean: agora #349 — a closure handed to a runner grows `( vec_at other 0 )` while a slice of `vv[0]` is kept
// The shape the fix must keep: the effect names only the capture the expression is rooted at (agora #349).
// main cd8c0a6: runs clean.
// map: §2.11 | A2 | runs-clean | - | agora #349: a closure growing another Vec's element inline
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ run ( @ v ) f → v {
    ( f )
}

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    : ( Vec ( Vec u ) ) other ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [( Vec u )] other ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    ( run \ → v { ( vec_reserve [u] ( vec_at [( Vec u )] other 0 ) 4096 ) } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
