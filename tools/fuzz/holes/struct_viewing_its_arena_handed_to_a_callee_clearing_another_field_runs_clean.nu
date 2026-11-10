// struct_viewing_its_arena_handed_to_a_callee_clearing_another_field_runs_clean: agora #600 — the self-viewing struct handed to a callee that clears only `. t other` (`0.other`): per-field drop summaries leave the arena's views alone
// Control for agora #600.
// map: §2.10 | A2 | runs-clean | - | agora #600: the self-viewing struct handed to a callee that clears only `. t other` (`0.other`): per-field drop summaries leave the arena's views alone
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

@ reset_other Tk t → v {
    ( vec_push [String] . t other ( string_from `an unrelated string, long enough for the heap` ) )
    ( vec_clear [String] . t other )
}

@ main → i {
    : Tk t @ Tk { ( vec_new [String] ) ( vec_new [s] ) ( vec_new [String] ) }
    ( fill t )
    ( reset_other t )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
