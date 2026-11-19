// parameter_pushed_into_an_element_view_local_read_runs_clean: a parameter pushed into `x0`, a `( vec_at xss 0 )` binding, and only read
// Closed: only a change of the payload through the local is summarised (agora #793): the shape the fix must keep.
// main 977a74c: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #793: a parameter pushed into x0, a ( vec_at xss 0 ) binding, and only read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ ch ( Rc ( Vec u ) ) h → v {
    : ( Vec ( Vec ( Rc ( Vec u ) ) ) ) xss ( vec_new [( Vec ( Rc ( Vec u ) ) )] )
    ( vec_push [( Vec ( Rc ( Vec u ) ) )] xss ( vec_new [( Rc ( Vec u ) )] ) )
    : ( Vec ( Rc ( Vec u ) ) ) x0 ( vec_at [( Vec ( Rc ( Vec u ) ) )] xss 0 )
    ( vec_push [( Rc ( Vec u ) )] x0 h )
    ( nurl_println_int ( vec_len [u] ( rc_get [( Vec u )] ( vec_at [( Rc ( Vec u ) )] ( vec_at [( Vec ( Rc ( Vec u ) ) )] xss 0 ) 0 ) ) ) )
}

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
