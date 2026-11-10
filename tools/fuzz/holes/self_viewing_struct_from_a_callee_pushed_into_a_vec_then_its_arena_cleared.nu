// self_viewing_struct_from_a_callee_pushed_into_a_vec_then_its_arena_cleared: agora #600 — `( vec_push vs ( make ) )`: the element's view of its own arena has no path in `vs` — refused, bind it first (formal's review of #600's plan)
// base e07e6e35 (#1720 on main): accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #600: `( vec_push vs ( make ) )`: the element's view of its own arena has no path in `vs` — refused, bind it first (formal's review of #600's plan)
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
    : ( Vec Tk ) vs ( vec_new [Tk] )
    ( vec_push [Tk] vs ( make ) )
    : Tk t ( vec_at [Tk] vs 0 )
    ( vec_clear [String] . t arena )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
