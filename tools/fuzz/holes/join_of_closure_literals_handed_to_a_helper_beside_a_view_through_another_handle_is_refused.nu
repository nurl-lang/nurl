// join_of_closure_literals_handed_to_a_helper_beside_a_view_through_another_handle_is_refused: a `?` join of two closure literals, one replacing an Rc's payload, handed to a helper that runs it; a slice taken through another handle is read after
// Closed: agora #838, a closure argument that is a join, a block or a match is asked by the closures it may be.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #838: a join of closure literals handed to a helper replaces an Rc's payload beside a view
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ run ( @ v ) f → v { ( f ) }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : b k T
    ( run ? k \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } \ → v {} )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
