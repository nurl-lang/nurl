// closure_over_a_parameters_element_handed_back_and_run_past_its_vec: agora #483 — a function returns a closure (bound, then handed back) over a `vec_at` binding of its parameter's element; the caller frees the Vec and runs it
// Closed: a `~^k` handed back answers `^k`, so the caller ties the closure to its argument's elements (agora #483).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #483: a closure over a parameter's element handed back and run past its Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first_reader ( Vec String ) v → ( @ i ) {
    : String e ( vec_at [String] v 0 )
    : ( @ i ) f \ → i { ^ ( strlen ( string_data e ) ) }
    ^ f
}

@ main → i {
    : ~ ( @ i ) g \ → i { ^ 0 }
    {
        : ( Vec String ) t ( vec_new [String] )
        ( vec_push [String] t ( string_from `a string its vector frees before the returned closure runs` ) )
        = g ( first_reader t )
    }
    ( nurl_println_int ( g ) )
    ^ 0
}
