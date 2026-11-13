// closure_given_a_changing_literal_below_its_run_in_a_foreach_loop_is_refused: a closure binding run in a `~ k ks` loop body and given, below the run, a literal that replaces an Rc's payload; a slice taken through another handle is read between the run and the assignment, freed on the next round
// Closed: agora #843, the loop's closure replay runs at its body block's close, for a loop over a container as for a `~ cond` one.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #843: a closure given a changing literal below its run in a loop over a Vec ends a view read after the run
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ~ ( Vec i ) ks ( vec_new [i] )
    ( vec_push [i] ks 1 )
    ( vec_push [i] ks 2 )
    : ~ ( @ v ) d \ → v {}
    ~ k ks {
        ( d )
        ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
        = d \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) }
    }
    ^ 0
}
