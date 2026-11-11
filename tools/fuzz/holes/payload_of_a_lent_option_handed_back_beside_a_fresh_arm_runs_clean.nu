// payload_of_a_lent_option_handed_back_beside_a_fresh_arm_runs_clean: agora #635 — `?? ( vec_get [D] v 0 ) { T x → { ^ x } F → { ^ ( bomb … ) } }`, v a borrowed parameter: the payload's owner slot says the Vec owns it, and the path answers so.
// Closed: `^ x` of a `??` payload that cannot be copied answers by the payload's owner slot — flag 0 while the Vec the call lent it out of owns it — or "lent" with no slot (gen_ret); what it is lent out of is in the return summary (mem_ret_param_lend_via_all).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #635: `?? ( vec_get [D] v 0 ) { T x → { ^ x } F → { ^ ( bomb … ) } }`, v a borrowed parameter: the payload's owner slot says the Vec owns it, and the path answers so
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ f ( Vec Bomb ) v → Bomb { ?? ( vec_get [Bomb] v 0 ) { T x → { ^ x } F → { ^ ( bomb `dflt` 0 ) } } }

@ main → i {
    : ~ ( Vec Bomb ) v ( vec_new [Bomb] )
    ( vec_push [Bomb] v ( bomb `e0` 0 ) )
    ( vec_push [Bomb] v ( bomb `e1` 0 ) )
    : Bomb r ( f v )
    ( see `main` r )
    : ~ ( Vec Bomb ) e ( vec_new [Bomb] )
    : Bomb r2 ( f e )
    ( see `main` r2 )
    ( nurl_println_int ( vec_len [Bomb] v ) )
    ^ 0
}
