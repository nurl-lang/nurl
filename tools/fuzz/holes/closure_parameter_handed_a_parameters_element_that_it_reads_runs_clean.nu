// closure_parameter_handed_a_parameters_element_that_it_reads_runs_clean: a closure parameter handed a parameter's element it only reads (the shape the fix must keep)
// Closed: the irealloc summary follows what the drop summary does: a closure body (a capture that is the enclosing function's parameter), a closure parameter called (its node, the literals its callers pass), and a `??` payload or a loop element of a parameter (__pderiv_reach) (agora #496).
// main 5e576b82: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #496: a closure parameter handed an element it reads
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ each0 ( Vec ( Vec u ) ) vv ( @ i ( Vec u ) ) f → i { ^ ( f ( vec_at [( Vec u )] vv 0 ) ) }

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w a )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( nurl_println_int ( each0 w \ ( Vec u ) z → i { ^ # i ( vec_len [u] z ) } ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
