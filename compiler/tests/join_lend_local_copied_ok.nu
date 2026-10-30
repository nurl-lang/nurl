// join_lend_local_copied_ok.nu — a `?` / `??` handed back whose value one
// of its arms' calls (or a try over one, or the scrutinee's call) lends out
// of a local: the local is dropped on the way out, so that path hands back
// a copy — at a `^`, as the function's fall-off value, and as a returned
// result's payload. A join lending a parameter stays a lend, and a caller
// returning it over its own local copies it (agora #198).

$ `stdlib/core/string.nu`

: | E { Bad }

: W { String s i n }

% Drop W { @ drop W w → v { ( nurl_print `drop ` ) ( nurl_println_int . w n ) } }

@ gets W w → String { ^ . w s }

@ getr W w → !String E { ^ @ !String E { T . w s } }

@ mkw s t i n → W { ^ @ W { ( string_from t ) n } }

@ fresh → !String E { ^ @ !String E { T ( string_from `fresh` ) } }

@ arm_ret b c → !String E {
    : W w ( mkw `an arm's call` 1 )
    ^ ? c ( getr w ) ( fresh )
}

@ match_arm_ret b c → !String E {
    : W w ( mkw `a match arm's call` 2 )
    ^ ?? c { T → ( getr w ) F → ( fresh ) }
}

@ try_arm_payload b c → !String E {
    : W w ( mkw `a try arm` 3 )
    ^ @ !String E { T ? c \ ( getr w ) ( string_from `fresh` ) }
}

@ scrutinee_payload → !String E {
    : W w ( mkw `the scrutinee's call` 4 )
    ^ @ !String E { T ?? ( getr w ) { T x → x F _ → ( string_from `bad` ) } }
}

@ fall_off b c → !String E {
    : W w ( mkw `a fall-off arm` 5 )
    ? c ( getr w ) ( fresh )
}

@ fall_off_match → String {
    : W w ( mkw `a fall-off scrutinee` 6 )
    ?? ( getr w ) { T x → x F _ → ( string_from `bad` ) }
}

@ block_join_payload b c → !String E {
    : W w ( mkw `a block ending in a join` 7 )
    ^ @ !String E { T { : i k 1 ? c ( gets w ) ( string_from `fresh` ) } }
}

// Lends part of its parameter: still a lend, which `outer` copies.
@ param_lend W w → String {
    ?? ( getr w ) { T x → x F _ → ( string_from `bad` ) }
}

@ outer → String {
    : W w ( mkw `a parameter's lend` 8 )
    ^ ( param_lend w )
}

@ show ! String E r → v {
    ?? r { T x → ( nurl_println ( string_data x ) ) F _ → ( nurl_println `bad` ) }
}

@ main → i {
    ( show ( arm_ret T ) )
    ( show ( arm_ret F ) )
    ( show ( match_arm_ret T ) )
    ( show ( try_arm_payload T ) )
    ( show ( try_arm_payload F ) )
    ( show ( scrutinee_payload ) )
    ( show ( fall_off T ) )
    : String m ( fall_off_match )
    ( nurl_println ( string_data m ) )
    ( show ( block_join_payload T ) )
    ( show ( block_join_payload F ) )
    : String o ( outer )
    ( nurl_println ( string_data o ) )
    ^ 0
}
