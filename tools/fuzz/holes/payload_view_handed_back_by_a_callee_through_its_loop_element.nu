// payload_view_handed_back_by_a_callee_through_its_loop_element: a callee looping over a Vec of shares and handing back a view of an element's payload, kept past `( wipe r )`
// Closed: …and a view through an element whose marks are not known in full (`pf_`), a holder a marked view was stored into, a `~` loop's element and cursor over a marked container, and a closure call's result (any payload) end too (agora #726).
// main 1a44e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #726: a payload view a callee hands back through its loop element, past a reset
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

@ last_view ( Vec ( Rc ( Vec u ) ) ) xs ( Vec u ) own → ( Slice u ) {
    : ~ ( Slice u ) cur ( slice_from_vec [u] own )
    ~ h xs {
        : ( Vec u ) p ( rc_get [( Vec u )] h )
        = cur ( slice_from_vec [u] p )
    }
    ^ cur
}

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    ( vec_push [u] v0 8 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs ( rc_clone [( Vec u )] r ) )
    : ( Vec u ) own ( vec_new [u] )
    ( vec_push [u] own 1 )
    : ( Slice u ) sl ( last_view hs own )
    ( wipe r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
