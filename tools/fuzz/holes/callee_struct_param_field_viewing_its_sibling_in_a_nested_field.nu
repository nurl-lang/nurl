// callee_struct_param_field_viewing_its_sibling_in_a_nested_field: `( bad . w inner )`, `. . w inner idx` viewing `. . w inner arena`
// Closed: a call handed a value whose field views another of its own fields (`vds_`, or a callee's `h>.^rel`), where the callee's final summaries say it may drop, replace or move the buffer of what that field holds, is refused: inside the callee the two are one parameter's unrelated fields (agora #606).
// main 029b01d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #606: ( bad . w inner ), its idx viewing its arena
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: A { ( Vec String ) arena ( Vec s ) idx }

: W { A inner i n }

@ bad A p → v {
    ( vec_clear [String] . p arena )
    ( nurl_println ( vec_at [s] . p idx 0 ) )
}

@ main → i {
    : W w @ W { @ A { ( vec_new [String] ) ( vec_new [s] ) } 0 }
    ( vec_push [String] . . w inner arena ( string_from `a heap string long enough to be on the heap for sure` ) )
    ( vec_push [s] . . w inner idx ( string_data ( vec_at [String] . . w inner arena 0 ) ) )
    ( bad . w inner )
    ^ 0
}
