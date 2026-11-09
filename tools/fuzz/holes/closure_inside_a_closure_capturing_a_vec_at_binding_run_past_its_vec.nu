// closure_inside_a_closure_capturing_a_vec_at_binding_run_past_its_vec: agora #483 — `g = \ → i { : f \ → i { strlen e } ^ ( f ) }` with `e = ( vec_at t 0 )`: a closure literal inside a closure; kept past `t`'s block, run after
// Closed: the closure's copy of the lent value's handle depends on the container's elements, `~^R` (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure inside a closure capturing a vec_at binding run past its Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( @ i ) g \ → i { ^ 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string its vector frees before the closure runs` ) )
        : String e ( vec_at [String] t 0 )
        = g \ → i {
            : ( @ i ) f \ → i { ^ ( strlen ( string_data e ) ) }
            ^ ( f )
        }
    }
    ( nurl_println_int ( g ) )
    ^ 0
}
