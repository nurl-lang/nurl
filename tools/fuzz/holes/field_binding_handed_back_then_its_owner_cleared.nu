// field_binding_handed_back_then_its_owner_cleared: agora #635 — `: D r ( fb ( vec_at [Holder] v 0 ) )  ( vec_clear [Holder] v )  … r`, fb handing back `: D e . h inner  ^ e`: r borrows from v.
// Closed: a value read out of somewhere else with no owner slot of its own — a `~` loop's element, a binding of a field read or of another binding, a `??` payload of one — is not the function's to hand over: part of a parameter the caller keeps, it is lent back and the return summary names the parameter; part of anything else, it is copied, or refused when it cannot be (`__lent_view_root`, gen_ret, gen_agg_lit).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #635: `: D r ( fb ( vec_at [Holder] v 0 ) )  ( vec_clear [Holder] v )  … r`, fb handing back `: D e . h inner  ^ e`: r borrows from v
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ fb Holder h → Bomb { : Bomb e . h inner ^ e }

@ main → i {
    : ~ ( Vec Holder ) v ( vec_new [Holder] )
    ( vec_push [Holder] v @ Holder { ( string_from `nm` ) ( bomb `mine.inner` 0 ) } )
    : Bomb r ( fb ( vec_at [Holder] v 0 ) )
    ( vec_clear [Holder] v )
    ( see `main` r )
    ^ 0
}
