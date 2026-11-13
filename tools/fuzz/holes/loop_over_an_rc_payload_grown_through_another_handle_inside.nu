// loop_over_an_rc_payload_grown_through_another_handle_inside: `~ x pv` over `( rc_get r2 )`, `( vec_reserve ( rc_get r ) 4096 )` inside, r a clone of r2
// Closed: a `~` loop over a payload lent out of an Rc share (`: ( Vec u ) pv ( rc_get r2 )`) holds a view of it through an element of the share, which the same-Rc rule ends when another handle may grow or replace the payload (agora #761 item 2).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #761: a loop over an Rc payload grown through another handle
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 1 )
    ( vec_push [u] v0 2 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec u ) pv ( rc_get [( Vec u )] r2 )
    : ~ i n 0
    ~ x pv {
        ( vec_reserve [u] ( rc_get [( Vec u )] r ) 4096 )
        = n + n # i x
    }
    ( nurl_println_int n )
    ^ 0
}
