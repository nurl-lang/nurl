// index_of_element_views_kept_across_an_arena_push_runs_clean: an index of element views kept across a push to the arena.
// The shape the fix must keep: views of elements (`^k`) survive the Vec growing.
// main 4d57d596: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #404: an index of element views kept across a push to the arena
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ index ( Vec String ) arena → ( Vec s ) {
    : ( Vec s ) idx ( vec_new [s] )
    : String e ( vec_at [String] arena 0 )
    ( vec_push [s] idx ( string_data e ) )
    ^ idx
}

@ main → i {
    : ~ ( Vec String ) arena ( vec_new [String] )
    ( vec_push [String] arena ( string_from `a heap string long enough to be on the heap for sure` ) )
    : ( Vec s ) idx ( index arena )
    ( vec_push [String] arena ( string_from `another one, also on the heap for sure` ) )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ^ 0
}
