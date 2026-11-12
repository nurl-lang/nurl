// view_of_a_payload_pushed_into_a_vec_of_views_past_a_reset: a slice of `( rc_get ( vec_at hs 0 ) )` pushed into a `( Vec ( Slice u ) )` and read out of it past `( wipe r )`
// Closed: …and a view through an element whose marks are not known in full (`pf_`), a holder a marked view was stored into, a `~` loop's element and cursor over a marked container, and a closure call's result (any payload) end too (agora #726).
// main 1a44e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #726: a view of a payload pushed into a Vec of views, past a reset
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
    : ( Vec ( Slice u ) ) vs ( vec_new [( Slice u )] )
    ( vec_push [( Slice u )] vs ( slice_from_vec [u] ( rc_get [( Vec u )] ( vec_at [( Rc ( Vec u ) )] hs 0 ) ) ) )
    ( wipe r )
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] vs 0 ) 0 ) )
    ^ 0
}
