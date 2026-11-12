// rc_payload_handed_to_a_helper_that_grows_an_element_past_a_view_through_a_clone: `( growelem ( rc_get r ) )` reserving `( vec_at p 0 )`, while a slice of that element is taken through `r2`
// Closed: the same-Rc rule asks the irealloc summary of the callee a share's payload is handed to (agora #712).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #712: an Rc payload handed to a helper that grows one of its elements, past a view through a clone
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
    : ( Rc ( Vec ( Vec u ) ) ) r2 ( rc_clone [( Vec ( Vec u ) )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( rc_get [( Vec ( Vec u ) )] r2 ) 0 ) )
    ( growelem ( rc_get [( Vec ( Vec u ) )] r ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
