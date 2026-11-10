// callee_leaving_a_holder_viewing_an_arena_element_kept_across_arena_pushes_runs_clean: agora #383 — the arena only grows while idx is read: its own buffer moves, the elements' buffers do not (the PO's arena_grow_bound)
// Control for agora #383.
// map: §2.10 | A2 | runs-clean | - | agora #383: the arena only grows while idx is read: its own buffer moves, the elements' buffers do not (the PO's arena_grow_bound)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
@ put ( Vec String ) arena ( Vec s ) idx String key → v {
    ( vec_push [String] arena key )
    : String e ( vec_at [String] arena - ( vec_len [String] arena ) 1 )
    ( vec_push [s] idx ( string_data e ) )
}
@ main → i {
    : ( Vec String ) arena ( vec_new [String] )
    : ( Vec s ) idx ( vec_new [s] )
    ( put arena idx ( string_from `the first key, long enough for the heap` ) )
    ( vec_push [String] arena ( string_from `a second key, long enough for the heap` ) )
    ( vec_push [String] arena ( string_from `a third key, long enough for the heap too` ) )
    ( vec_push [String] arena ( string_from `a fourth key, long enough for the heap too` ) )
    ( vec_push [String] arena ( string_from `a fifth key, long enough for the heap too!` ) )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ^ 0
}
