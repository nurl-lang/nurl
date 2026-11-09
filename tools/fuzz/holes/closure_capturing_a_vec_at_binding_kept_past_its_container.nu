// closure_capturing_a_vec_at_binding_kept_past_its_container: agora #483 — a closure literal captures a `vec_at` binding of a block-local Vec by value and outlives the Vec
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure capturing a vec_at binding kept past its container
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string freed at the end of its block, captured whole` ) )
        : String e ( vec_at [String] t 0 )
        = f \ → i { ^ ( strlen ( string_data e ) ) }
    }
    ( nurl_println_int ( f ) )  // heap-use-after-free
    ^ 0
}
