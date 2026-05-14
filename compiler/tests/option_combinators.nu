// Test: Option combinators (opt_is_some, opt_is_none, opt_unwrap_or,
//                            opt_map, opt_and_then)
$ `stdlib/core/option.nu`

@ main → i {
    : ?i some7 @ ?i { T 7 }
    : ?i none @ ?i { F 0 }

    // is_some / is_none
    ( nurl_print ? ( opt_is_some [i] some7 ) `som1\n` `som0\n` )
    ( nurl_print ? ( opt_is_some [i] none ) `som1\n` `som0\n` )
    ( nurl_print ? ( opt_is_none [i] none ) `non1\n` `non0\n` )
    ( nurl_print ? ( opt_is_none [i] some7 ) `non1\n` `non0\n` )

    // unwrap_or
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] some7 99 ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] none 99 ) ) ) ( nurl_print `\n` )

    // map: Some(7) → Some(49), None → None
    : ( @ i i ) square \ i x → i { ^ * x x }
    : ?i m1 ( opt_map [i i] some7 square )
    : ?i m2 ( opt_map [i i] none square )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] m1 0 ) ) ) ( nurl_print `\n` )
    ( nurl_print ? ( opt_is_none [i] m2 ) `map_none_ok\n` `map_none_bad\n` )

    // and_then: flatmap. halve_even(8)=Some(4), halve_even(7)=None
    : ( @ ?i i ) halve_even \ i x → ?i {
        ? == % x 2 0 { ^ @ ?i { T / x 2 } } { ^ @ ?i { F 0 } }
    }
    : ?i a1 ( opt_and_then [i i] @ ?i { T 8 } halve_even )
    : ?i a2 ( opt_and_then [i i] @ ?i { T 7 } halve_even )
    : ?i a3 ( opt_and_then [i i] none halve_even )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] a1 0 ) ) ) ( nurl_print `\n` )
    ( nurl_print ? ( opt_is_none [i] a2 ) `at2_none_ok\n` `at2_none_bad\n` )
    ( nurl_print ? ( opt_is_none [i] a3 ) `at3_none_ok\n` `at3_none_bad\n` )
    ^ 0
}
