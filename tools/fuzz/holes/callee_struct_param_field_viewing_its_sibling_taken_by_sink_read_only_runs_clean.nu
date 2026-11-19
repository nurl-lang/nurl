// callee_struct_param_field_viewing_its_sibling_taken_by_sink_read_only_runs_clean: a `sink` callee reads `. p arena`'s length and `. p idx`
// Closed: only a callee whose summary changes what the viewed field holds refuses the call (agora #606): the shape the fix must keep.
// main 029b01d: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #606: a sink callee reads . p arena's length and . p idx
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: A { ( Vec String ) arena ( Vec s ) idx }

@ bad sink A p → v {
    ( nurl_println_int # i ( vec_len [String] . p arena ) )
    ( nurl_println ( vec_at [s] . p idx 0 ) )
}

@ main → i {
    : A a @ A { ( vec_new [String] ) ( vec_new [s] ) }
    ( vec_push [String] . a arena ( string_from `a heap string long enough to be on the heap for sure` ) )
    ( vec_push [s] . a idx ( string_data ( vec_at [String] . a arena 0 ) ) )
    ( bad a )
    ^ 0
}
