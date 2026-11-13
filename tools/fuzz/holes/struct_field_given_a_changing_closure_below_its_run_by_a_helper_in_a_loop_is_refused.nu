// struct_field_given_a_changing_closure_below_its_run_by_a_helper_in_a_loop_is_refused: a struct handed to a helper that runs its closure field, in a `~` loop body that gives the field, below the call, a closure replacing an Rc's payload; a slice taken through another handle is read between, freed on the next round
// Closed: agora #843, the holder's node grows below the run, and the loop's replay runs at its body block's close.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #843: a struct's closure field given a changing closure below its run in a loop ends a view read after the run
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
    : ~ C c @ C { \ → v {} 1 }
    : ~ i k 0
    ~ < k 2 {
        ( runc c )
        ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
        = . c go \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) }
        = k + k 1
    }
    ^ 0
}
