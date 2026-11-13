// builders_struct_of_a_returned_closure_read_back_out_and_run_beside_a_view_is_refused: a builder hands back a struct holding a maker's closure that grows the builder's Rc parameter's payload; the closure is read back out of the field and run beside a slice taken after the builder call (claude-finish's st08, #817's review)
// Closed: agora #838, a function handing back a holder answers what its closures do to the parameters (`retcloeff`), which its caller's holder carries.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #838: a builder's struct of a maker's closure, read back out and run, grows an Rc's payload beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( @ v ) f i n }

@ mkr ( Rc ( Vec u ) ) r → ( @ v ) { ^ \ → v { ( vec_reserve [u] ( rc_get [( Vec u )] r ) 4096 ) } }

@ mkh ( Rc ( Vec u ) ) r → H { ^ @ H { ( mkr r ) 1 } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : H h ( mkh r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    : ( @ v ) g . h f
    ( g )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
