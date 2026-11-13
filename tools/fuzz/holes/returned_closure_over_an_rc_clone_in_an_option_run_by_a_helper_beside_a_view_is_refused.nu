// returned_closure_over_an_rc_clone_in_an_option_run_by_a_helper_beside_a_view_is_refused: a maker's closure over an rc_clone of its Rc parameter, replacing the payload, in an option literal run by a helper; a slice taken through another handle after the option is made is read after
// Closed: agora #845, an rc_clone of a parameter is one Rc value with it, and the holder carries the maker's answer.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #845: a maker's closure over an rc_clone, in an option run by a helper, replaces the payload beside a view
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ runo ? ( @ v ) o → v { ?? o { T g → { ( g ) } F → {} } }

@ mk ( Rc ( Vec u ) ) h → ( @ v ) {
    : ( Rc ( Vec u ) ) c ( rc_clone [( Vec u )] h )
    ^ \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) }
}

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ?( @ v ) o @ ?( @ v ) { T ( mk r ) }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( runo o )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
