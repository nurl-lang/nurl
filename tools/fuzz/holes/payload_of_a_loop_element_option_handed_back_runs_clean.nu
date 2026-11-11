// payload_of_a_loop_element_option_handed_back_runs_clean: agora #635 — `~ o v { ?? o { T x → { ^ x } F → {} } }` over a `( Vec ?D )` parameter, with a fresh fall-back.
// Closed: a value read out of somewhere else with no owner slot of its own — a `~` loop's element, a binding of a field read or of another binding, a `??` payload of one — is not the function's to hand over: part of a parameter the caller keeps, it is lent back and the return summary names the parameter; part of anything else, it is copied, or refused when it cannot be (`__lent_view_root`, gen_ret, gen_agg_lit).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #635: `~ o v { ?? o { T x → { ^ x } F → {} } }` over a `( Vec ?D )` parameter, with a fresh fall-back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ f ( Vec ? Bomb ) v → Bomb {
    ~ o v { ?? o { T x → { ^ x } F → {} } }
    ^ ( bomb `dflt` 0 )
}

@ main → i {
    : ~ ( Vec ? Bomb ) v ( vec_new [? Bomb] )
    ( vec_push [? Bomb] v @ ?Bomb { T ( bomb `e0` 0 ) } )
    ( vec_push [? Bomb] v @ ?Bomb { F } )
    : Bomb r ( f v )
    ( see `main` r )
    ( nurl_println_int ( vec_len [? Bomb] v ) )
    ^ 0
}
