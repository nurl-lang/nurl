// returned_closure_in_a_struct_run_by_a_helper_beside_a_view_through_another_handle_is_refused: a closure a maker hands back, replacing its Rc parameter's payload, stored in a struct literal's field, the struct run by a helper; a slice taken through another handle after the maker call is read after
// Closed: agora #838, a call handing back a closure whose effects its maker's answer gives is a member doing those, which a holder carries.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #838: a maker's closure stored in a struct and run by a helper replaces an Rc's payload beside a view
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ runc C c → v { : ( @ v ) g . c go ( g ) }

@ mk ( Rc ( Vec u ) ) h → ( @ v ) {
    ^ \ → v { ( rc_set [( Vec u )] h ( vec_new [u] ) ) }
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
