// returned_closure_over_an_rc_clone_in_a_struct_run_by_a_helper_beside_a_view_is_refused: a maker's closure over an rc_clone of its Rc parameter, replacing the payload, stored in a struct literal and run by a helper; a slice taken through another handle after the struct is made is read after
// Closed: agora #845, an rc_clone of a parameter is one Rc value with it, and the holder carries the maker's answer.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #845: a maker's closure over an rc_clone, in a struct run by a helper, replaces the payload beside a view
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ runc C c → v { : ( @ v ) g . c go ( g ) }

@ mk ( Rc ( Vec u ) ) h → ( @ v ) {
    : ( Rc ( Vec u ) ) c ( rc_clone [( Vec u )] h )
    ^ \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) }
}

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : C cc @ C { ( mk r ) 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( runc cc )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
