// rc_share_held_in_a_struct_handed_to_a_helper_that_clears_its_payload_past_a_view_through_a_clone: `: H { ( Rc ( Vec ( Vec u ) ) ) a i n }` holding `r`, handed to `@ wipe H h` that clears `( rc_get . h a )`, while a slice of an element is taken through `r2`, a clone of `r`
// Closed: the same-Rc rule asks whether the Rc types two values reach meet — a struct holding a share reaches its Rc (agora #712).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #712: a share held in a struct handed to a helper that clears the payload, past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec ( Vec u ) ) ) a i n }

@ wipe H h → v { ( vec_clear [( Vec u )] ( rc_get [( Vec ( Vec u ) )] . h a ) ) }

@ main → i {
    : ( Vec ( Vec u ) ) v0 ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] v0 ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] v0 0 ) 7 )
    : ( Rc ( Vec ( Vec u ) ) ) r ( rc_new [( Vec ( Vec u ) )] v0 )
    : ( Rc ( Vec ( Vec u ) ) ) r2 ( rc_clone [( Vec ( Vec u ) )] r )
    : H h @ H { r 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( rc_get [( Vec ( Vec u ) )] r2 ) 0 ) )
    ( wipe h )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
