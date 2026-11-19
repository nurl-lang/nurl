// callee_struct_param_field_viewing_its_sibling_grown: the viewed String grown through `. p arena` in the callee, then `. p idx` read
// Closed: a call handed a value whose field views another of its own fields (`vds_`, or a callee's `h>.^rel`), where the callee's final summaries say it may drop, replace or move the buffer of what that field holds, is refused: inside the callee the two are one parameter's unrelated fields (agora #606).
// main 029b01d: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #606: the viewed String grown through . p arena, then . p idx read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: A { ( Vec String ) arena ( Vec s ) idx }

@ bad A p → v {
    ( string_push_str ( vec_at [String] . p arena 0 ) `, and a tail long enough to move the buffer elsewhere on the heap` )
    ( nurl_println ( vec_at [s] . p idx 0 ) )
}

@ main → i {
    : A a @ A { ( vec_new [String] ) ( vec_new [s] ) }
    ( vec_push [String] . a arena ( string_from `a heap string long enough to be on the heap for sure` ) )
    ( vec_push [s] . a idx ( string_data ( vec_at [String] . a arena 0 ) ) )
    ( bad a )
    ^ 0
}
