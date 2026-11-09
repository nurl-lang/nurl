// element_of_an_rc_payload_grown_inline_through_another_handle_past_a_slice: agora #349 — a slice of the payload's element taken through one Rc handle; the element grown inline through another handle of the same Rc
// Closed: the `@sx` row of the inline lend reaches the same-Rc rule, as a call handed the payload does (agora #349).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: an element of an rc payload grown inline through another handle past a slice
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec ( Vec u ) ) v0 ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] v0 ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] v0 0 ) 7 )
    : ( Rc ( Vec ( Vec u ) ) ) r ( rc_new [( Vec ( Vec u ) )] v0 )
    : ( Rc ( Vec ( Vec u ) ) ) r2 ( rc_clone [( Vec ( Vec u ) )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( rc_get [( Vec ( Vec u ) )] r2 ) 0 ) )
    ( vec_reserve [u] ( vec_at [( Vec u )] ( rc_get [( Vec ( Vec u ) )] r ) 0 ) 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
