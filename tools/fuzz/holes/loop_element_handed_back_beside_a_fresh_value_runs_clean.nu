// loop_element_handed_back_beside_a_fresh_value_runs_clean: agora #635 — `~ x v { … ^ x … }` beside `^ ( bomb … )`, v a borrowed Vec parameter of values that cannot be copied: the element is lent back, the fresh value handed over.
// Closed: a value read out of somewhere else with no owner slot of its own — a `~` loop's element, a binding of a field read or of another binding, a `??` payload of one — is not the function's to hand over: part of a parameter the caller keeps, it is lent back and the return summary names the parameter; part of anything else, it is copied, or refused when it cannot be (`__lent_view_root`, gen_ret, gen_agg_lit).
// main: accepted; AddressSanitizer reported heap-use-after-free (the element dropped by the caller and by its Vec).
// map: §7.6 | A2 | runs-clean | - | agora #635: `~ x v { … ^ x … }` beside `^ ( bomb … )`, v a borrowed Vec parameter of values that cannot be copied: the element is lent back, the fresh value handed over
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ f ( Vec Bomb ) v → Bomb {
    ~ x v { ? == . x boom 0 { ^ x } {} }
    ^ ( bomb `none-found` 0 )
}

@ main → i {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `e0` 0 ) )
    ( vec_push [Bomb] v ( bomb `e1` 0 ) )
    : Bomb r ( f v )
    ( see `main` r )
    ( nurl_println_int ( vec_len [Bomb] v ) )
    ^ 0
}
