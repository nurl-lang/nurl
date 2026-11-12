// payload_of_a_parameters_element_grown_through_a_match: `?? ( vec_get w 0 ) { T e → { ( vec_reserve e 4096 ) } F → {} }` in `top`, past the caller's slice of element 0
// Closed: the irealloc summary follows what the drop summary does: a closure body (a capture that is the enclosing function's parameter), a closure parameter called (its node, the literals its callers pass), and a `??` payload or a loop element of a parameter (__pderiv_reach) (agora #496).
// main 5e576b82: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #496: a `??` payload of a parameter's element grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ top ( Vec ( Vec u ) ) w → v { ?? ( vec_get [( Vec u )] w 0 ) { T e → { ( vec_reserve [u] e 4096 ) } F → {} } }

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
