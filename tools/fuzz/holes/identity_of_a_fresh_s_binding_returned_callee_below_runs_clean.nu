// identity_of_a_fresh_s_binding_returned_callee_below_runs_clean: agora #478 — `^ ( same a )` through an identity function defined below, a an `s` given a fresh string: the text `same` lends back is copied at the return, as it is when `same` is defined above (AGORA-867, AGORA-946 D4b), and a is released as usual
// main ebc1b407: accepted; heap-use-after-free. Then refused (agora #478) while the order of the two functions decided; one answer since AGORA-867.
// map: §2.10 | A2 | runs-clean | - | agora #478 / AGORA-867: `^ ( same a )` through an identity function defined below, a an `s` given a fresh string: copied at the return whatever the order
$ `stdlib/core/string.nu`

@ label → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( same a )
}

@ same s x → s { ^ x }

@ main → i { ( nurl_println ( label ) ) ^ 0 }
