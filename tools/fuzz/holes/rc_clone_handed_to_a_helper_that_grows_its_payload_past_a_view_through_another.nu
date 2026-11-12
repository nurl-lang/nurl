// rc_clone_handed_to_a_helper_that_grows_its_payload_past_a_view_through_another: `( grow r )` with `@ grow ( Rc ( Vec ( Vec u ) ) ) a` reserving an element of `( rc_get a )`, while a slice of that element is taken through `r2`, a clone of `r`
// Closed: the same-Rc rule asks the irealloc summary, which is what a callee growing its Rc parameter's payload records (agora #601 item 2).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #601: an Rc handed to a helper that grows an element of its payload, past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ grow ( Rc ( Vec ( Vec u ) ) ) a → v {
    ( vec_reserve [u] ( vec_at [( Vec u )] ( rc_get [( Vec ( Vec u ) )] a ) 0 ) 4096 )
}

@ main → i {
    : ( Vec ( Vec u ) ) v0 ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] v0 ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] v0 0 ) 7 )
    : ( Rc ( Vec ( Vec u ) ) ) r ( rc_new [( Vec ( Vec u ) )] v0 )
    : ( Rc ( Vec ( Vec u ) ) ) r2 ( rc_clone [( Vec ( Vec u ) )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( rc_get [( Vec ( Vec u ) )] r2 ) 0 ) )
    ( grow r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
