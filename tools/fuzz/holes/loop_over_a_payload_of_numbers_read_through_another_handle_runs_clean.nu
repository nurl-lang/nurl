// loop_over_a_payload_of_numbers_read_through_another_handle_runs_clean: AGORA-774 guard — `~ x pl` over an Rc payload of numbers, a callee that only reads it through another handle: accepted
// map: §2.5 | A2 | runs-clean | - | AGORA-774 guard: a read through another handle
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( nurl_println_int ( vec_len [u] ( rc_get [( Vec u )] r ) ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    ( vec_push [u] v0 8 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec u ) pl ( rc_get [( Vec u )] r2 )
    : ~ i n 0
    ~ x pl {
        ( wipe r )
        = n + n # i x
    }
    ( nurl_println_int n )
    ^ 0
}
