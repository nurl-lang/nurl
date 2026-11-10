// struct_whose_index_field_views_its_arena_field_returned_whole_runs_clean: agora #383 — the same done in place: an owner handed back whole that views its own fields answers so (`.^arena` in g_fn_rviews, agora #600)
// main 87895b72: refused (`returns a view of 't'`) — a self-view handed back whole was taken for a view of a released local.
// map: §2.10 | A2 | runs-clean | - | agora #383: the same done in place: an owner handed back whole that views its own fields answers so (`.^arena` in g_fn_rviews, agora #600)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tk { ( Vec String ) arena ( Vec s ) idx }

@ put ( Vec String ) arena ( Vec s ) idx String key → v {
    ( vec_push [String] arena key )
    : String e ( vec_at [String] arena - ( vec_len [String] arena ) 1 )
    ( vec_push [s] idx ( string_data e ) )
}

@ make → Tk {
    : Tk t @ Tk { ( vec_new [String] ) ( vec_new [s] ) }
    ( vec_push [String] . t arena ( string_from `the first key, long enough for the heap` ) )
    : String e ( vec_at [String] . t arena 0 )
    ( vec_push [s] . t idx ( string_data e ) )
    ^ t
}

@ main → i {
    : Tk t ( make )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
