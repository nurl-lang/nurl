// closure_over_a_vec_at_binding_run_after_its_vec_moved_into_another_is_cleared: agora #483 — `f` over `e = ( vec_at t 0 )`; `t` stored into `vv` (its elements now `vv`'s element's); `vv` cleared; `f` run
// Closed: a holder of a copy of the handle in an element of a value stored into an owner holds one in an element of that owner's element (bck_borrow_transfer, agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a vec_at binding run after the Vec it moved into is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
        : String e ( vec_at [String] t 0 )
        = f \ → i { ^ ( strlen ( string_data e ) ) }
        ( vec_push [( Vec String )] vv t )
    }
    ( vec_clear [( Vec String )] vv )
    ( nurl_println_int ( f ) )
    ^ 0
}
