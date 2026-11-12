// element_bound_through_one_rc_handle_grown_past_a_view_through_another: `: ( Vec u ) e ( vec_at p 0 )` with `p` the payload of `r`, grown with `vec_reserve`, while a slice of that element is taken through `r2`, a clone of `r` (agora #497's own spelling)
// Closed: the element is lent out of a share, and the same-Rc rule asks the share it was lent out of (agora #566, #497).
// main 3b63ee3b: refused; stays refused.
// map: §2.10 | A2 | rejected | - | agora #497: an element bound through one Rc handle and grown, past a view through another
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec ( Vec u ) ) v0 ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] v0 ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] v0 0 ) 7 )
    : ( Rc ( Vec ( Vec u ) ) ) r ( rc_new [( Vec ( Vec u ) )] v0 )
    : ( Rc ( Vec ( Vec u ) ) ) r2 ( rc_clone [( Vec ( Vec u ) )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( rc_get [( Vec ( Vec u ) )] r2 ) 0 ) )
    : ( Vec ( Vec u ) ) p ( rc_get [( Vec ( Vec u ) )] r )
    : ( Vec u ) e ( vec_at [( Vec u )] p 0 )
    ( vec_reserve [u] e 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
