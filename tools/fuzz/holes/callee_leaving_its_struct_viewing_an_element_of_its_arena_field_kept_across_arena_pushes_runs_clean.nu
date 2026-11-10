// callee_leaving_its_struct_viewing_an_element_of_its_arena_field_kept_across_arena_pushes_runs_clean: agora #600 — the same, the arena only grown: its own buffer moves, its Strings' do not
// Control for agora #600.
// map: §2.10 | A2 | runs-clean | - | agora #600: the same, the arena only grown: its own buffer moves, its Strings' do not
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tk { ( Vec String ) arena ( Vec s ) idx ( Vec String ) other }

@ put ( Vec String ) arena ( Vec s ) idx String key → v {
    ( vec_push [String] arena key )
    : String e ( vec_at [String] arena - ( vec_len [String] arena ) 1 )
    ( vec_push [s] idx ( string_data e ) )
}

@ fill Tk t → v {
    ( put . t arena . t idx ( string_from `the first key, long enough for the heap` ) )
}

@ make → Tk {
    : Tk t @ Tk { ( vec_new [String] ) ( vec_new [s] ) ( vec_new [String] ) }
    ( fill t )
    ^ t
}

@ main → i {
    : Tk t @ Tk { ( vec_new [String] ) ( vec_new [s] ) ( vec_new [String] ) }
    ( fill t )
    ( vec_push [String] . t arena ( string_from `another key, long enough for the heap` ) )
    ( vec_push [String] . t arena ( string_from `a third key, long enough for the heap too` ) )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
