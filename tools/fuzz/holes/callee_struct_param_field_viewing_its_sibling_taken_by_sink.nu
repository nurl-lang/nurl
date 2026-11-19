// callee_struct_param_field_viewing_its_sibling_taken_by_sink: `@ bad sink A p` takes `a` over, clears `. p arena` and reads `. p idx`
// Closed: a call handed a value whose field views another of its own fields (`vds_`, or a callee's `h>.^rel`), where the callee's final summaries say it may drop, replace or move the buffer of what that field holds, is refused: inside the callee the two are one parameter's unrelated fields (agora #606).
// main 029b01d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #606: bad takes a over (sink), clears . p arena and reads . p idx
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: A { ( Vec String ) arena ( Vec s ) idx }

@ bad sink A p → v {
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
