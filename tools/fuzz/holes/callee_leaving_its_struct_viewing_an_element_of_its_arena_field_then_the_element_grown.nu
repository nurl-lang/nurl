// callee_leaving_its_struct_viewing_an_element_of_its_arena_field_then_the_element_grown: agora #600 — the same, then the viewed String grown in place
// base 3c05d83d (#1720): accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #600: the same, then the viewed String grown in place
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
    : String e0 ( vec_at [String] . t arena 0 )
    ( string_push_str e0 `, and a tail long enough to move the buffer elsewhere on the heap` )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
