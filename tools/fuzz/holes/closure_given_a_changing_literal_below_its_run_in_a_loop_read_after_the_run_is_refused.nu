// closure_given_a_changing_literal_below_its_run_in_a_loop_read_after_the_run_is_refused: a closure binding run in a `~` loop body and given, below the run, a literal that replaces an Rc's payload; a slice taken through another handle is read between the run and the assignment, freed on the next round
// Closed: agora #843, the loop's closure replay (#686) runs at its body block's close, before the back edge: the next round starts from it.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #843: a closure given a changing literal below its run in a loop ends a view read after the run on the next round
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ runc C c → v { : ( @ v ) g . c go ( g ) }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ~ ( @ v ) d \ → v {}
    : ~ i k 0
    ~ < k 2 {
        ( d )
        ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
        = d \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) }
        = k + k 1
    }
    ^ 0
}
