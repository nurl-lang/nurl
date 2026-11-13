// loop_over_an_rc_payload_grown_by_a_helper_handed_another_handle: `~ x pv` over `( rc_get r2 )`, `( grow r )` inside, grow reserving through r
// Closed: a `~` loop over a payload lent out of an Rc share (`: ( Vec u ) pv ( rc_get r2 )`) holds a view of it through an element of the share, which the same-Rc rule ends when another handle may grow or replace the payload (agora #761 item 2).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #761: a loop over an Rc payload grown by a helper handed another handle
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ grow ( Rc ( Vec u ) ) r → v { ( vec_reserve [u] ( rc_get [( Vec u )] r ) 4096 ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 1 )
    ( vec_push [u] v0 2 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec u ) pv ( rc_get [( Vec u )] r2 )
    : ~ i n 0
    ~ x pv {
        ( grow r )
        = n + n # i x
    }
    ( nurl_println_int n )
    ^ 0
}
