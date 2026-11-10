// callee_exit_pair_nested_in_a_join: agora #558 — the same inside a `?` join
// Refused on main and with #558, which keeps a nested call's own rows ahead of the enclosing call's checks.
// map: §2.10 | A2 | rejected | - | agora #558: the same inside a `?` join
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ f inout W w inout String s → i { = w @ W { ( string_data s ) } ^ 0 }

@ id i x → i { ^ x }

@ k i z inout W w inout String s → i {
    ( string_push_str s `and a long tail that makes the buffer move, more than the first capacity holds` )
    ( nurl_println . w v )
    ^ 0
}

@ k2 i z s v inout String s → v {
    ( string_push_str s `and a long tail that makes the buffer move, more than the first capacity holds` )
    ( nurl_println v )
}

@ main → i {
    : ~ W w @ W { `x` }
    : ~ String s ( string_from `the first heap string, long enough to be on the heap for sure` )
    : b c T
    : i r ? c ( id ( k ( f w s ) w s ) ) 0
    ^ 0
}
