// string_loop_element_of_a_local_vec_handed_back_runs_clean: agora #635 — `~ x loc { … ^ x … }` and `^ @ ?String { T x }`, loc a local Vec of Strings dropped on the way out: the caller gets a copy.
// Closed: a value read out of somewhere else with no owner slot of its own — a `~` loop's element, a binding of a field read or of another binding, a `??` payload of one — is not the function's to hand over: part of a parameter the caller keeps, it is lent back and the return summary names the parameter; part of anything else, it is copied, or refused when it cannot be (`__lent_view_root`, gen_ret, gen_agg_lit).
// main: accepted; AddressSanitizer reported heap-use-after-free (the element was lent out of the Vec the return released).
// map: §7.6 | A2 | runs-clean | - | agora #635: `~ x loc { … ^ x … }` and `^ @ ?String { T x }`, loc a local Vec of Strings dropped on the way out: the caller gets a copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ f → String {
    : ~ ( Vec String ) loc ( vec_new [String] )
    ( vec_push [String] loc ( string_from `a local element long enough for the heap` ) )
    ~ x loc { ? > ( string_len x ) 2 { ^ x } {} }
    ^ ( string_from `none` )
}

@ g → ?String {
    : ~ ( Vec String ) loc ( vec_new [String] )
    ( vec_push [String] loc ( string_from `another local element, long enough too` ) )
    ~ x loc { ? > ( string_len x ) 2 { ^ @ ?String { T x } } {} }
    ^ @ ?String { F }
}

@ main → i {
    : String r ( f )
    ( nurl_println ( string_data r ) )
    : ?String o ( g )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
