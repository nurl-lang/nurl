// loop_over_a_parameters_rc_payload_grown_through_another_parameter: `~ x pv` over `( rc_get a )`, `( grow b )` inside, a and b one Rc value at the call
// Closed: a `~` loop over a payload lent out of an Rc share (`: ( Vec u ) pv ( rc_get r2 )`) holds a view of it through an element of the share, which the same-Rc rule ends when another handle may grow or replace the payload (agora #761 item 2).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #761: a loop over a parameter's Rc payload grown through another parameter
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ grow ( Rc ( Vec u ) ) r → v { ( vec_reserve [u] ( rc_get [( Vec u )] r ) 4096 ) }

@ walk ( Rc ( Vec u ) ) a ( Rc ( Vec u ) ) b → i {
    : ( Vec u ) pv ( rc_get [( Vec u )] a )
    : ~ i n 0
    ~ x pv {
        ( grow b )
        = n + n # i x
    }
    ^ n
}

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 1 )
    ( vec_push [u] v0 2 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    ( nurl_println_int ( walk r r2 ) )
    ^ 0
}
