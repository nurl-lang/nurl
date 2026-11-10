// struct_viewing_its_arena_handed_to_a_callee_clearing_the_arena: agora #600 — the self-viewing struct handed to `reset_arena`, which clears `. t arena` (its drop summary `0.arena`)
// base 3c05d83d (#1720): accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #600: the self-viewing struct handed to `reset_arena`, which clears `. t arena` (its drop summary `0.arena`)
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

@ reset_arena Tk t → v { ( vec_clear [String] . t arena ) }

@ main → i {
    : Tk t @ Tk { ( vec_new [String] ) ( vec_new [s] ) ( vec_new [String] ) }
    ( fill t )
    ( reset_arena t )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
