// slice_read_after_it_moved_to_another_binding_is_refused: agora #545 — `= e a` hands a's buffer to e; `= e [i | 8 8]` then frees it, and the loop over `a` read freed memory. No rule knew `a` had been moved from.
// Closed: a slice moves as a String does: `= e a` and `: [i r a` consume `a`, and the borrow checker refuses a read of it afterwards (use of moved value).
// main (before this PR): accepted; AddressSanitizer, heap-use-after-free.
// map: §2.1 | A2 | rejected | - | agora #545: an owned slice assigned to another binding, which then released it, was read on through the first name (UAF)
@ main → i {
    : [i a [i | 5 6]
    : ~ [i e [i | 7]
    = e a
    = e [i | 8 8]
    ~ x a { ( nurl_println ( nurl_str_int x ) ) }
    ^ 0
}
