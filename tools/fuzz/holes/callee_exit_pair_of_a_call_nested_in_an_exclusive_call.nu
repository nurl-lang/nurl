// callee_exit_pair_of_a_call_nested_in_an_exclusive_call: agora #558 — `( k ( f w s ) w s )`: f leaves w viewing s, and k grows s then reads w — the outer call's check sees the inner call's exit (claude-formal's counterexample to the first #558 change)
// Refused on main and with #558, which keeps a nested call's own rows ahead of the enclosing call's checks.
// map: §2.10 | A2 | rejected | - | agora #558: `( k ( f w s ) w s )`: f leaves w viewing s, and k grows s then reads w — the outer call's check sees the inner call's exit (claude-formal's counterexample to the first #558 change)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ f inout W w inout String s → i { = w @ W { ( string_data s ) } ^ 0 }

@ id i x → i { ^ x }

@ k i z inout W w inout String s → v {
    ( string_push_str s `and a long tail that makes the buffer move, more than the first capacity holds` )
    ( nurl_println . w v )
}

@ k2 i z s v inout String s → v {
    ( string_push_str s `and a long tail that makes the buffer move, more than the first capacity holds` )
    ( nurl_println v )
}

@ main → i {
    : ~ W w @ W { `x` }
    : ~ String s ( string_from `the first heap string, long enough to be on the heap for sure` )
    : b c T
    ( k ( f w s ) w s )
    ^ 0
}
