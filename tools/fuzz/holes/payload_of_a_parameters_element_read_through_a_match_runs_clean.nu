// payload_of_a_parameters_element_read_through_a_match_runs_clean: `?? ( vec_get w 0 ) { T e → # i ( vec_len e ) … }` (the shape the fix must keep)
// Closed: the irealloc summary follows what the drop summary does: a closure body (a capture that is the enclosing function's parameter), a closure parameter called (its node, the literals its callers pass), and a `??` payload or a loop element of a parameter (__pderiv_reach) (agora #496).
// main 5e576b82: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #496: a `??` payload of a parameter's element read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ top ( Vec ( Vec u ) ) w → i { ^ ?? ( vec_get [( Vec u )] w 0 ) { T e → # i ( vec_len [u] e ) F → 0 } }

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    : ( Vec u ) a ( vec_new [u] )
    ( vec_push [u] a 7 )
    ( vec_push [( Vec u )] w a )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( nurl_println_int ( top w ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
