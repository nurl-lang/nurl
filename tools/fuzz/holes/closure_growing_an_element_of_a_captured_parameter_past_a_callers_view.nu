// closure_growing_an_element_of_a_captured_parameter_past_a_callers_view: a closure in `top` runs `( vec_reserve ( vec_at vv 0 ) 4096 )` on the captured parameter `vv`, while the caller keeps a slice of `w`'s element 0
// Closed: the irealloc summary follows what the drop summary does: a closure body (a capture that is the enclosing function's parameter), a closure parameter called (its node, the literals its callers pass), and a `??` payload or a loop element of a parameter (__pderiv_reach) (agora #496).
// main 5e576b82: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #496: a closure growing an element of a captured parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ top ( Vec ( Vec u ) ) vv → v {
    : ( @ v ) g \ → v { ( vec_reserve [u] ( vec_at [( Vec u )] vv 0 ) 4096 ) }
    ( g )
}

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w a )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( top w )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
