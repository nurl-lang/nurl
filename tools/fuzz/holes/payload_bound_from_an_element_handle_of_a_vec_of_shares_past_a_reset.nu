// payload_bound_from_an_element_handle_of_a_vec_of_shares_past_a_reset: `: ( Rc ( Vec u ) ) h ( vec_at hs 0 )`, `: ( Vec u ) p ( rc_get h )` and a slice of `p`, kept past `( wipe r )`
// Closed: …and a view through an element whose marks are not known in full (`pf_`), a holder a marked view was stored into, a `~` loop's element and cursor over a marked container, and a closure call's result (any payload) end too (agora #726).
// main 1a44e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #726: a payload bound from an element handle of a Vec of shares, past a reset
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    ( vec_push [u] v0 8 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs ( rc_clone [( Vec u )] r ) )
    : ( Rc ( Vec u ) ) h ( vec_at [( Rc ( Vec u ) )] hs 0 )
    : ( Vec u ) p ( rc_get [( Vec u )] h )
    : ( Slice u ) sl ( slice_from_vec [u] p )
    ( wipe r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
