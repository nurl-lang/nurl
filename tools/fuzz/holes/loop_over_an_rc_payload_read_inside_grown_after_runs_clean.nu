// loop_over_an_rc_payload_read_inside_grown_after_runs_clean: `~ x pv` over `( rc_get r2 )` reading through r inside, growing through r after the loop
// Kept: a loop over an Rc payload that another handle only reads inside, and grows after the loop, is accepted (agora #761 item 2).
// main 83059aae: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #761: a loop over an Rc payload read through another handle
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
        = n + n # i ( vec_len [u] ( rc_get [( Vec u )] r ) )
        = n + n # i x
    }
    ( vec_reserve [u] ( rc_get [( Vec u )] r ) 4096 )
    ( nurl_println_int n )
    ^ 0
}
