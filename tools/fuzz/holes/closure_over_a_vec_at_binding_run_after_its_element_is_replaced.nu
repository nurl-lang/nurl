// closure_over_a_vec_at_binding_run_after_its_element_is_replaced: agora #483 — a closure over a `vec_at` binding run after `vec_set` replaced that element
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a vec_at binding run after its element is replaced
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `the first string, replaced while the closure holds its handle` ) )
    : ~ ( @ i ) f \ → i { ^ 0 }
    {
        : String e ( vec_at [String] t 0 )
        = f \ → i { ^ ( strlen ( string_data e ) ) }
    }
    ( vec_set [String] t 0 ( string_from `a replacement, long enough for a heap buffer` ) )
    ( nurl_println_int ( f ) )
    ^ 0
}
