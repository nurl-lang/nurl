// closure_read_from_an_rc_payload_vec_changed_through_another_handle_runs_clean:
// `( vec_at [( @ i i )] ( rc_get r ) 0 )` bound, then the Vec cleared through a
// binding of `( rc_get r2 )` on a second handle of the same Rc. Since agora #552
// a closure read out of a Vec is lent, but only out of a Vec the frame owns
// by name: the walk does not see a change made through another Rc handle
// (agora #345), so here the read stays a copy and the call runs on its own env.
// map: §8.4 | A2 | runs-clean | - | a closure read out of an Rc payload's Vec, the Vec then cleared through a binding of rc_get on a second handle: the read stays a copy (agora #552, #345).
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ mk i n → ( @ i i ) {
    : String s ( string_from `hello` )
    ^ \ i x → i { ^ + x ( string_len s ) }
}

@ main → i {
    : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] )
    ( vec_push [( @ i i )] fs ( mk 0 ) )
    : ( Rc ( Vec ( @ i i ) ) ) r ( rc_new [( Vec ( @ i i ) )] fs )
    : ( Rc ( Vec ( @ i i ) ) ) r2 ( rc_clone [( Vec ( @ i i ) )] r )
    : ( @ i i ) f ( vec_at [( @ i i )] ( rc_get [( Vec ( @ i i ) )] r ) 0 )
    : ( Vec ( @ i i ) ) v2 ( rc_get [( Vec ( @ i i ) )] r2 )
    ( vec_clear [( @ i i )] v2 )
    ( nurl_println_int ( f 10 ) )
    ^ 0
}
