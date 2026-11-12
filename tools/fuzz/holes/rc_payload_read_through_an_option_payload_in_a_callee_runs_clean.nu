// rc_payload_read_through_an_option_payload_in_a_callee_runs_clean: agora #734 — as rc_payload_replaced_through_an_option_payload_in_a_callee_past_a_view_through_another_share, the callee only reading the payload
// Control: a callee that only reads through the derived binding drops nothing (agora #734, #735).
// main 851e5cb3: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #734: as rc_payload_replaced_through_an_option_payload_in_a_callee_past_a_view_through_another_share, the callee only reading the payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ ch ? ( Rc ( Vec u ) ) o → v { ?? o { T h → { ( nurl_println_int ( vec_len [u] ( rc_get [( Vec u )] h ) ) ) } F _ → {} } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ?( Rc ( Vec u ) ) o @ ?( Rc ( Vec u ) ) { T r }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch o )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
