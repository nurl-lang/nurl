// closure_binding_put_into_a_struct_run_by_a_helper_beside_a_view_is_refused: a closure binding capturing an Rc put into a struct literal (`@ C { f 1 }`), the struct handed to a helper that runs it; a slice taken through another handle is read after
// Closed: agora #736, a literal's field is the binding's node.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: a closure binding put into a struct, run by a helper, replaces an Rc's payload beside a view
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ runc C c → v { : ( @ v ) g . c go ( g ) }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ( @ v ) f \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) }
    : C c @ C { f 1 }
    ( runc c )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
