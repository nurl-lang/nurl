// generic_closure_parameter_handed_a_parameters_element_that_it_grows: the generic `each0 [T]` spelling of the same, at `[u]`
// Closed: the irealloc summary follows what the drop summary does: a closure body (a capture that is the enclosing function's parameter), a closure parameter called (its node, the literals its callers pass), and a `??` payload or a loop element of a parameter (__pderiv_reach) (agora #496).
// main 5e576b82: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #496: a generic closure parameter handed a parameter's element it grows
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ each0 [T] ( Vec ( Vec T ) ) vv ( @ v ( Vec T ) ) f → v { ( f ( vec_at [( Vec T )] vv 0 ) ) }

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w a )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( each0 [u] w \ ( Vec u ) z → v { ( vec_reserve [u] z 4096 ) } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
