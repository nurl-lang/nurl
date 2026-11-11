// generic_identity_over_an_option_parameter_handed_back_runs_clean: agora #635 — `^ ( gid [?D] p )`, p a borrowed option parameter: lent back.
// Closed: a function that hands back, as is, the result of a callee that lends the argument at which it passed a parameter of its own lends that parameter (mem_fn_lends reads the `callee:position:parameter` notes, __retfwd_note), whichever of the two is compiled first.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #635: `^ ( gid [?D] p )`, p a borrowed option parameter: lent back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: Holder { String name Bomb inner }

@ see s what Bomb b → v { ( nurl_println ( nurl_str_cat3 what ` sees ` ( string_data . b tag ) ) ) }

@ gid [A] A x → A { ^ x }

@ f ? Bomb p → ?Bomb { ^ ( gid [? Bomb] p ) }

@ main → i {
    : ?Bomb mine @ ?Bomb { T ( bomb `mine` 0 ) }
    : ?Bomb r ( f mine )
    ?? r { T b → { ( see `main` b ) } F → {} }
    ?? mine { T b → { ( see `main` b ) } F → {} }
    ^ 0
}
