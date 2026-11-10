// self_viewing_struct_returned_by_a_callee_then_another_field_cleared_runs_clean: agora #600 — the same struct, then only `. t other` cleared
// Control for agora #600.
// map: §2.10 | A2 | runs-clean | - | agora #600: the same struct, then only `. t other` cleared
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
    : Tk t ( make )
    ( vec_push [String] . t other ( string_from `an unrelated string, long enough for the heap` ) )
    ( vec_clear [String] . t other )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
