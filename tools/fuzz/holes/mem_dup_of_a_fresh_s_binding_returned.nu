// mem_dup_of_a_fresh_s_binding_returned: agora #478 — `^ ( mem_dup a )`, a an `s` given a fresh string: the copy is a second name of a's buffer, which is released at the return
// main ebc1b407: accepted; heap-use-after-free (the ret row took the call for a handed over by name).
// map: §2.10 | A2 | rejected | - | agora #478: `^ ( mem_dup a )`, a an `s` given a fresh string: the copy is a second name of a's buffer, which is released at the return
$ `stdlib/core/string.nu`

@ label → s {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ ( mem_dup a )
}

@ main → i { ( nurl_println ( label ) ) ^ 0 }
