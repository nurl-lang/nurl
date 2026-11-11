// loop_struct_element_handed_back_beside_a_fresh_one_runs_clean: agora #635 — `~ x v { … ^ x … }` beside a fresh literal, the element a struct holding a value that cannot be copied; and the same through nested loops and a field path (`~ x . h items`).
// Closed: a value read out of somewhere else with no owner slot of its own — a `~` loop's element, a binding of a field read or of another binding, a `??` payload of one — is not the function's to hand over: part of a parameter the caller keeps, it is lent back and the return summary names the parameter; part of anything else, it is copied, or refused when it cannot be (`__lent_view_root`, gen_ret, gen_agg_lit).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #635: `~ x v { … ^ x … }` beside a fresh literal, the element a struct holding a value that cannot be copied; and the same through nested loops and a field path (`~ x . h items`)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

: SE { String name Bomb b }

: Box { ( Vec Bomb ) items i n }

@ f ( Vec SE ) v → SE {
    ~ x v { ? == . . x b boom 0 { ^ x } {} }
    ^ @ SE { ( string_from `fresh` ) ( bomb `fresh` 0 ) }
}

@ g ( Vec ( Vec Bomb ) ) vv → Bomb {
    ~ row vv { ~ x row { ? == . x boom 0 { ^ x } {} } }
    ^ ( bomb `none` 0 )
}

@ k Box h → Bomb {
    ~ x . h items { ? == . x boom 0 { ^ x } {} }
    ^ ( bomb `none` 0 )
}

@ main → i {
    : ~ ( Vec SE ) v ( vec_new [SE] )
    ( vec_push [SE] v @ SE { ( string_from `n0` ) ( bomb `e0` 0 ) } )
    : SE r ( f v )
    ( see `main` . r b )
    ( nurl_println_int ( vec_len [SE] v ) )
    : ~ ( Vec ( Vec Bomb ) ) vv ( vec_new [( Vec Bomb )] )
    : ~ ( Vec Bomb ) row ( vec_new [Bomb] )
    ( vec_push [Bomb] row ( bomb `r0` 0 ) )
    ( vec_push [( Vec Bomb )] vv row )
    : Bomb r2 ( g vv )
    ( see `main` r2 )
    : ~ ( Vec Bomb ) it ( vec_new [Bomb] )
    ( vec_push [Bomb] it ( bomb `i0` 0 ) )
    : Box h @ Box { it 1 }
    : Bomb r3 ( k h )
    ( see `main` r3 )
    ( nurl_println_int ( vec_len [Bomb] . h items ) )
    ^ 0
}
