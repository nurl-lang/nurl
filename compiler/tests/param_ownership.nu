// Test: Phase 2B parameter ownership. A fresh allocation passed inline as
// a function argument must be freed after the call returns; nested arg
// allocations follow the same rule via each gen_call's own temp list.

@ greet s name → v {
    ( nurl_print `Hello, ` ) ( nurl_print name ) ( nurl_print `!\n` )
}

@ main → i {
    // Direct case: callee borrows the inline-allocated string.
    ( greet ( nurl_str_cat `Wo` `rld` ) )
    // Nested case: each level's allocation should be released by its own
    // enclosing call's cleanup.
    ( greet ( nurl_str_cat ( nurl_str_cat `Ne` `st` ) `ed` ) )
    // Mixed: literal + fresh allocation.
    ( nurl_print ( nurl_str_cat `Done: ` `42` ) ) ( nurl_print `\n` )
    ^ 0
}
