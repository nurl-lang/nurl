// closure_replacing_an_rc_field_run_by_a_function_beside_a_view_is_refused: the replacing closure handed to a function that runs it
// Closed: agora #736, a closure handed to a call runs there: its effects are replayed with their Rc types.
// main ff75baea: accepted; ASan reported heap-use-after-free on 3 runs in 3.
// map: §2.2 | A2 | rejected | - | agora #736: a function running a closure that replaces an Rc field beside a view
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { ( Rc ( Vec u ) ) a i n }

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : H h @ H { r 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ( @ v ) f \ → v { ( rc_set [( Vec u )] . h a ( vec_new [u] ) ) }
    ( run f )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
