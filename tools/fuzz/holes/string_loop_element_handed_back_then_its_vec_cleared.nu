// string_loop_element_handed_back_then_its_vec_cleared: agora #635 — `: String r ( f v )  ( vec_clear [String] v )  … r`, f handing back a `~` loop's element of its parameter beside a fresh String: r borrows from v.
// Closed: a value read out of somewhere else with no owner slot of its own — a `~` loop's element, a binding of a field read or of another binding, a `??` payload of one — is not the function's to hand over: part of a parameter the caller keeps, it is lent back and the return summary names the parameter; part of anything else, it is copied, or refused when it cannot be (`__lent_view_root`, gen_ret, gen_agg_lit).
// main: accepted; AddressSanitizer reported heap-use-after-free (the return summary did not name the parameter, so the caller's binding was no borrow of v).
// map: §7.6 | A2 | rejected | - | agora #635: `: String r ( f v )  ( vec_clear [String] v )  … r`, f handing back a `~` loop's element of its parameter beside a fresh String: r borrows from v
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ f ( Vec String ) v → String {
    ~ x v { ? > ( string_len x ) 2 { ^ x } {} }
    ^ ( string_from `none-found` )
}

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element long enough for the heap` ) )
    : String r ( f v )
    ( vec_clear [String] v )
    ( nurl_println ( string_data r ) )
    ^ 0
}
