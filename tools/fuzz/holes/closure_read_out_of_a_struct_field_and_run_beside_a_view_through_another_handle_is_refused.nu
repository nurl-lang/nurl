// closure_read_out_of_a_struct_field_and_run_beside_a_view_through_another_handle_is_refused: a closure capturing an Rc, stored in a struct's field, read back out (`: ( @ v ) g . c go`) and run; a slice of the payload taken through another handle is read after
// Closed: agora #736, a closure read out of a holder is one of the closures stored into it.
// main 923fa94a: accepted; ASan reported heap-use-after-free.
// map: §2.2 | A2 | rejected | - | agora #736: a closure read out of a struct's field and run replaces an Rc's payload beside a view through another handle
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( @ v ) go i n }

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : C c @ C { \ → v { ( rc_set [( Vec u )] r ( vec_new [u] ) ) } 1 }
    : ( @ v ) g . c go
    ( g )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ 0
}
