// closure_over_a_vec_at_binding_run_after_its_vec_is_cleared_through_a_cursor: agora #483 — a closure over a `vec_at` binding run after its Vec's elements were cleared through `cur`, a copy of the Vec's handle
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a vec_at binding run after its Vec is cleared through a cursor
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string cleared before the closure holding its handle runs` ) )
    : ~ ( Vec String ) cur t
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : String e ( vec_at [String] t 0 )
        = f \ → i { ^ ( strlen ( string_data e ) ) }
    }
    ( vec_clear [String] cur )
    ( nurl_println_int ( f ) )
    ^ 0
}
