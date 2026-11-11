// field_binding_of_a_parameter_handed_back_runs_clean: agora #635 — `: D e . h inner  ^ e`, h a borrowed parameter — on its own, beside a fresh value in a branch, through a second binding (`: D e2 e`), and of a parameter itself (`: D e p  ^ e`): lent back as `^ . h inner` and `^ p` are.
// Closed: a value read out of somewhere else with no owner slot of its own — a `~` loop's element, a binding of a field read or of another binding, a `??` payload of one — is not the function's to hand over: part of a parameter the caller keeps, it is lent back and the return summary names the parameter; part of anything else, it is copied, or refused when it cannot be (`__lent_view_root`, gen_ret, gen_agg_lit).
// main: accepted; AddressSanitizer reported heap-use-after-free (the field dropped by the caller and by its struct).
// map: §7.6 | A2 | runs-clean | - | agora #635: `: D e . h inner  ^ e`, h a borrowed parameter — on its own, beside a fresh value in a branch, through a second binding (`: D e2 e`), and of a parameter itself (`: D e p  ^ e`): lent back as `^ . h inner` and `^ p` are
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ fb Holder h → Bomb { : Bomb e . h inner ^ e }

@ fc Holder h b c → Bomb {
    ? c { : Bomb e . h inner : Bomb e2 e ^ e2 } {}
    ^ ( bomb `fresh` 0 )
}

@ fp Bomb p → Bomb { : Bomb e p ^ e }

@ main → i {
    : Holder h @ Holder { ( string_from `nm` ) ( bomb `mine.inner` 0 ) }
    : Bomb r ( fb h )
    ( see `main` r )
    : Bomb r2 ( fc h T )
    ( see `main` r2 )
    : Bomb r3 ( fc h F )
    ( see `main` r3 )
    : Bomb r4 ( fp r )
    ( see `main` r4 )
    ( see `main` . h inner )
    ^ 0
}
