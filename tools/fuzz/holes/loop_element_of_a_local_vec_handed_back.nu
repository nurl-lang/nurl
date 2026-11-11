// loop_element_of_a_local_vec_handed_back: agora #635 — `~ x loc { … ^ x … }`, loc a local Vec of values that cannot be copied, dropped on the way out: there is no lend the caller could keep.
// Closed: a value read out of somewhere else with no owner slot of its own — a `~` loop's element, a binding of a field read or of another binding, a `??` payload of one — is not the function's to hand over: part of a parameter the caller keeps, it is lent back and the return summary names the parameter; part of anything else, it is copied, or refused when it cannot be (`__lent_view_root`, gen_ret, gen_agg_lit).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #635: `~ x loc { … ^ x … }`, loc a local Vec of values that cannot be copied, dropped on the way out: there is no lend the caller could keep
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ f → Bomb {
    : ~ ( Vec Bomb ) loc ( vec_new [Bomb] )
    ( vec_push [Bomb] loc ( bomb `l0` 0 ) )
    ~ x loc { ? == . x boom 0 { ^ x } {} }
    ^ ( bomb `none` 0 )
}

@ main → i {
    : Bomb r ( f )
    ( see `main` r )
    ^ 0
}
