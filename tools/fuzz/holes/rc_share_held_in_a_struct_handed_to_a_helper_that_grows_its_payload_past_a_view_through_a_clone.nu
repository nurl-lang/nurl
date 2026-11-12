// rc_share_held_in_a_struct_handed_to_a_helper_that_grows_its_payload_past_a_view_through_a_clone: a struct holding `r` handed to a helper that reserves an element of `( rc_get . h a )`, while a slice of that element is taken through `r2`
// Closed: the same-Rc rule asks the callee's irealloc summary too (a callee that moves the buffer of an element of what it is handed), and a struct holding a share reaches its Rc (agora #712, #497).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #712: a share held in a struct handed to a helper that grows an element of the payload, past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a i n }

@ grow H h → v { ( vec_reserve [u] ( rc_get [( Vec u )] . h a ) 4096 ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : H h @ H { r 1 }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( grow h )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
