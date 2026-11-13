// returned_closure_in_a_struct_read_back_out_and_run_beside_a_view_is_refused: a closure a maker hands back, growing its Rc parameter's payload, bound, put into a struct literal, read back out of the field and run; a slice of the payload taken after the struct was made is read after (claude-finish's st01, #817's review)
// Closed: agora #838, a binding of a call handing back a closure with a `retcloeff` answer is a member doing those effects, which a holder carries.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #838: a maker's closure put into a struct, read back out and run, grows an Rc's payload beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( @ v ) f i n }

@ mkr ( Rc ( Vec u ) ) r → ( @ v ) { ^ \ → v { ( vec_reserve [u] ( rc_get [( Vec u )] r ) 4096 ) } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( @ v ) c ( mkr r )
    : H h @ H { c 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    : ( @ v ) g . h f
    ( g )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
