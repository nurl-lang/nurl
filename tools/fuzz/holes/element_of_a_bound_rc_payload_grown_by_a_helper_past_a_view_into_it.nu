// element_of_a_bound_rc_payload_grown_by_a_helper_past_a_view_into_it: `: ( Vec ( Vec u ) ) p ( rc_get r )`, `( growelem p )`, while a slice of `( vec_at ( rc_get r ) 0 )` is held
// Closed: the irealloc summary of a callee handed a borrow is asked as its realloc summary is (agora #497).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #497: an element of a bound Rc payload grown by a helper, past a view into it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ growelem ( Vec ( Vec u ) ) p → v { ( vec_reserve [u] ( vec_at [( Vec u )] p 0 ) 4096 ) }

@ main → i {
    : ( Vec ( Vec u ) ) v0 ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] v0 ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] v0 0 ) 7 )
    : ( Rc ( Vec ( Vec u ) ) ) r ( rc_new [( Vec ( Vec u ) )] v0 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( rc_get [( Vec ( Vec u ) )] r ) 0 ) )
    : ( Vec ( Vec u ) ) p ( rc_get [( Vec ( Vec u ) )] r )
    ( growelem p )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
