// closure_binding_lent_a_closure_then_given_its_own_in_an_arm: a `: ~` closure binding assigned a field's closure, then, in an arm, a literal; called after the arm. And the other order: a lent closure assigned in an arm only.
// Closed: a slot binding assigned a closure that is not its own stays in the owned-closure list — its slot says on each path what is left to release — and is marked as no owner to move from (mem_clo_mark_lent). Taken off the list, the literal's env assigned in the arm was an entry the arm had added, released at the arm's end, and the binding was called after it; and on the path that skipped a lent assignment in an arm, the env the binding still owned was released by nobody (agora #614).
// main b7ca325: accepted; AddressSanitizer: heap-use-after-free (`after`), LeakSanitizer: the env, on the call that skips the assignment (`skipped`).
// map: §7.5 | A2 | runs-clean | - | agora #614: a closure binding lent a closure and given its own in an arm — the env released at the arm's end, or by nobody on the other path
: Holder {
    ( @ i ) cb
    i pad
}

@ after i x → i {
    : ~ ( @ i ) f \ → i { ^ 0 }
    : Holder h @ Holder { \ → i { ^ x } 0 }
    = f . h cb
    ? > x 10 { = f \ → i { ^ + x 1 } } {}
    ^ ( f )
}

@ skipped i x → i {
    : ~ ( @ i ) f \ → i { ^ + x 5 }
    : Holder h @ Holder { \ → i { ^ x } 0 }
    ? > x 10 { = f . h cb } {}
    ^ ( f )
}

@ main → i {
    ( nurl_println ( nurl_str_int ( after 42 ) ) )
    ( nurl_println ( nurl_str_int ( after 2 ) ) )
    ( nurl_println ( nurl_str_int ( skipped 42 ) ) )
    ( nurl_println ( nurl_str_int ( skipped 2 ) ) )
    ^ 0
}
