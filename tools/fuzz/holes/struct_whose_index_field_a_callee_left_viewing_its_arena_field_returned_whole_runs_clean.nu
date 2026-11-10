// struct_whose_index_field_a_callee_left_viewing_its_arena_field_returned_whole_runs_clean: agora #383 — `put . t arena . t idx key` in the function that builds `t`, then `^ t`: the function's answer says its result views its own arena (`.^arena`), and the caller's binding is tied to that field of itself
// Control for agora #383 / #600.
// map: §2.10 | A2 | runs-clean | - | agora #383: `put . t arena . t idx key` in the function that builds `t`, then `^ t`: the function's answer says its result views its own arena (`.^arena`), and the caller's binding is tied to that field of itself
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
    ( put . t arena . t idx ( string_from `the first key, long enough for the heap` ) )
    ^ t
}

@ main → i {
    : Tk t ( make )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
