// option_of_a_closure_run_by_a_helper_beside_a_view_through_another_handle_is_refused: an option of a closure capturing an Rc handed to a helper that matches it and runs the payload; a slice taken through another handle is read after
// Closed: agora #736, an option of a closure is a holder like a struct.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: an option of a closure run by a helper replaces an Rc's payload beside a view
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ runo ? ( @ v ) o → v { ?? o { T g → { ( g ) } F → {} } }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ?( @ v ) o @ ?( @ v ) { T \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } }
    ( runo o )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
