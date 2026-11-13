// vec_of_closures_run_by_a_helper_beside_a_view_taken_after_the_push_is_refused: a closure capturing an Rc pushed into a Vec; a slice of the payload taken through another handle after the push; a helper runs the Vec's element; the slice is read after
// Closed: agora #736, the push stores the closure into the Vec, which carries it to the helper's call.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: a Vec's closure run by a helper replaces an Rc's payload beside a view taken after the push
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ runall ( Vec ( @ v ) ) fs → v { ?? ( vec_get [( @ v )] fs 0 ) { T g → { ( g ) } F → {} } }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ~ ( Vec ( @ v ) ) fs ( vec_new [( @ v )] )
    ( vec_push [( @ v )] fs \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( runall fs )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
