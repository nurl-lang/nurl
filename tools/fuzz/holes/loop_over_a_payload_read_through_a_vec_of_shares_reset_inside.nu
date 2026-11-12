// loop_over_a_payload_read_through_a_vec_of_shares_reset_inside: `~ x pl { ( wipe r ) … ( string_len x ) }` with `pl` the payload of `( vec_at hs 0 )`
// Closed: …and a view through an element whose marks are not known in full (`pf_`), a holder a marked view was stored into, a `~` loop's element and cursor over a marked container, and a closure call's result (any payload) end too (agora #726).
// main 1a44e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #726: a loop over a payload read through a Vec of shares, reset inside
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec String ) ) r → v { ( vec_clear [String] ( rc_get [( Vec String )] r ) ) ( vec_shrink_to_fit [String] ( rc_get [( Vec String )] r ) ) }

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `alpha beta gamma delta` ) )
    ( vec_push [String] v0 ( string_from `epsilon zeta eta theta` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Vec ( Rc ( Vec String ) ) ) hs ( vec_new [( Rc ( Vec String ) )] )
    ( vec_push [( Rc ( Vec String ) )] hs ( rc_clone [( Vec String )] r ) )
    : ( Vec String ) pl ( rc_get [( Vec String )] ( vec_at [( Rc ( Vec String ) )] hs 0 ) )
    : ~ i n 0
    ~ x pl {
        ( wipe r )
        = n + n ( string_len x )
    }
    ( nurl_println_int n )
    ^ 0
}
