// struct_of_a_mem_dup_of_a_fresh_s_binding_returned: agora #478 — `^ @ W { ( mem_dup a ) }`, a an `s` given a fresh string: the literal's field is a second name of a's buffer, released at the return
// main ebc1b407: accepted; heap-use-after-free (a view returned as written, not by name, read as one handed over).
// map: §2.10 | A2 | rejected | - | agora #478: `^ @ W { ( mem_dup a ) }`, a an `s` given a fresh string: the literal's field is a second name of a's buffer, released at the return
$ `stdlib/core/string.nu`

: W { s v }

@ label → W {
    : s a ( nurl_str_cat `a fresh string, ` `long enough for a heap buffer` )
    ^ @ W { ( mem_dup a ) }
}

@ main → i { : W w ( label ) ( nurl_println . w v ) ^ 0 }
