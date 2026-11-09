// closure_over_a_vec_at_binding_copied_and_kept_past_its_vec: agora #483 — a closure over a `vec_at` binding bound first, then copied into an outer binding (`: g f`), kept past the Vec's block
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a vec_at binding, copied and kept past its Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( @ i ) g \ → i { ^ 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string its vector frees before the copied closure runs` ) )
        : String e ( vec_at [String] t 0 )
        : ( @ i ) f \ → i { ^ ( strlen ( string_data e ) ) }
        = g f
    }
    ( nurl_println_int ( g ) )
    ^ 0
}
