// closure_growing_an_element_inline_with_its_slice_read_before_runs_clean: agora #349 — the slice of the element read before the closure that grows it runs
// The shape the fix must keep: a view read before the change (agora #349).
// main 21a0fb5: runs clean.
// map: §2.11 | A2 | runs-clean | - | agora #349: a closure growing an element inline, its slice read before
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    : ( @ v ) g \ → v { ( vec_reserve [u] ( vec_at [( Vec u )] vv 0 ) 4096 ) }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ( g )
    ^ 0
}
