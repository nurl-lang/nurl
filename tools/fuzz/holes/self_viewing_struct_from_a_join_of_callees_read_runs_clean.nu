// self_viewing_struct_from_a_join_of_callees_read_runs_clean: agora #600 — the join bound and read (yoloe-demo's `= tkz ? … ( tokenizer_load … ) ( tokenizer_load_builtin )`)
// Control for agora #600.
// map: §2.10 | A2 | runs-clean | - | agora #600: the join bound and read (yoloe-demo's `= tkz ? … ( tokenizer_load … ) ( tokenizer_load_builtin )`)
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
    : b c T
    : Tk t ? c ( make ) ( make )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
