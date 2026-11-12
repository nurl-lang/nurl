// closure_growing_its_own_local_runs_clean: a closure growing a Vec of its own body, beside a captured parameter (the shape the fix must keep)
// Closed: the irealloc summary follows what the drop summary does: a closure body (a capture that is the enclosing function's parameter), a closure parameter called (its node, the literals its callers pass), and a `??` payload or a loop element of a parameter (__pderiv_reach) (agora #496).
// main 5e576b82: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #496: a closure growing its own local
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ top ( Vec ( Vec u ) ) vv → v {
    : ( @ v ) g \ → v { : ~ ( Vec u ) x ( vec_new [u] ) ( vec_reserve [u] x 4096 ) ( nurl_println_int # i ( vec_len [u] x ) ) }
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
