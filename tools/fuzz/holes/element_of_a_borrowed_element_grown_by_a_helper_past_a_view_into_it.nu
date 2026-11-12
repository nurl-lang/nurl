// element_of_a_borrowed_element_grown_by_a_helper_past_a_view_into_it: `: ( Vec ( Vec u ) ) q ( vec_at outer 0 )`, `( growelem q )` reserving `( vec_at q 0 )`, while a slice of `( vec_at ( vec_at outer 0 ) 0 )` is held
// Closed: a callee that moves the buffer of an element of a borrow ends the views a level below the borrow's own buffer, as a callee moving the borrow's own buffer ends those at its level (agora #497).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #497: an element of a borrowed element grown by a helper, past a view into it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`

@ growelem ( Vec ( Vec u ) ) p → v { ( vec_reserve [u] ( vec_at [( Vec u )] p 0 ) 4096 ) }

@ main → i {
    : ( Vec ( Vec ( Vec u ) ) ) outer ( vec_new [( Vec ( Vec u ) )] )
    : ( Vec ( Vec u ) ) mid ( vec_new [( Vec u )] )
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    ( vec_push [( Vec u )] mid inner )
    ( vec_push [( Vec ( Vec u ) )] outer mid )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] outer 0 ) 0 ) )
    : ( Vec ( Vec u ) ) q ( vec_at [( Vec ( Vec u ) )] outer 0 )
    ( growelem q )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
