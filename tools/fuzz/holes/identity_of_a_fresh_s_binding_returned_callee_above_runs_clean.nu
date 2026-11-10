// identity_of_a_fresh_s_binding_returned_callee_above_runs_clean: agora #478 — `^ ( same a )` through an identity function defined above: codegen knows the call hands its argument back and hands a's own value over
// Control for agora #478: no release of a at the return.
// map: §2.10 | A2 | runs-clean | - | agora #478: `^ ( same a )` through an identity function defined above: codegen knows the call hands its argument back and hands a's own value over
$ `stdlib/core/string.nu`

@ same s x → s { ^ x }

@ label → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( same a )
}

@ main → i { ( nurl_println ( label ) ) ^ 0 }
