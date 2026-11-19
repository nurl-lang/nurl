// callee_struct_param_field_viewing_its_sibling: `@ bad A p` clears `. p arena` and reads `. p idx`, handed `a` whose `idx` views `arena`'s Strings
// Closed: a call handed a value whose field views another of its own fields (`vds_`, or a callee's `h>.^rel`), where the callee's final summaries say it may drop, replace or move the buffer of what that field holds, is refused: inside the callee the two are one parameter's unrelated fields (agora #606).
// main 029b01d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #606: inside a callee, a struct parameter whose field views another field (vec_clear . p arena, then read . p idx)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: A { ( Vec String ) arena ( Vec s ) idx }

@ bad A p → v {
    ( vec_clear [String] . p arena )
    ( nurl_println ( vec_at [s] . p idx 0 ) )
}

@ main → i {
    : A a @ A { ( vec_new [String] ) ( vec_new [s] ) }
    ( vec_push [String] . a arena ( string_from `a heap string long enough to be on the heap for sure` ) )
    ( vec_push [s] . a idx ( string_data ( vec_at [String] . a arena 0 ) ) )
    ( bad a )
    ^ 0
}
