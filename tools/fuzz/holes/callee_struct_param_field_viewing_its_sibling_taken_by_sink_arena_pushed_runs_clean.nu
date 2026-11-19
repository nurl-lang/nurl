// callee_struct_param_field_viewing_its_sibling_taken_by_sink_arena_pushed_runs_clean: a `sink` callee pushes into `. p arena` and reads `. p idx`
// Closed: only a callee whose summary changes what the viewed field holds refuses the call (agora #606): the shape the fix must keep.
// main 029b01d: accepted, runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #606: a sink callee pushes into . p arena and reads . p idx
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: A { ( Vec String ) arena ( Vec s ) idx }

@ bad sink A p → v {
    ( vec_push [String] . p arena ( string_from `another heap string long enough to be on the heap` ) )
    ( nurl_println ( vec_at [s] . p idx 0 ) )
}

@ main → i {
    : A a @ A { ( vec_new [String] ) ( vec_new [s] ) }
    ( vec_push [String] . a arena ( string_from `a heap string long enough to be on the heap for sure` ) )
    ( vec_push [s] . a idx ( string_data ( vec_at [String] . a arena 0 ) ) )
    ( bad a )
    ^ 0
}
