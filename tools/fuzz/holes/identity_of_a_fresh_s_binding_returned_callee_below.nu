// identity_of_a_fresh_s_binding_returned_callee_below: agora #478 — `^ ( same a )` through an identity function defined below, a an `s` given a fresh string: a second name of a's buffer, released at the return
// main ebc1b407: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #478: `^ ( same a )` through an identity function defined below, a an `s` given a fresh string: a second name of a's buffer, released at the return
$ `stdlib/core/string.nu`

@ label → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( same a )
}

@ same s x → s { ^ x }

@ main → i { ( nurl_println ( label ) ) ^ 0 }
