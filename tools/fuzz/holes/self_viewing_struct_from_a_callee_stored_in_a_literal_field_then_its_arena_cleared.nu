// self_viewing_struct_from_a_callee_stored_in_a_literal_field_then_its_arena_cleared: agora #600 — `: W w @ W { ( make ) }`: a literal's field, not the binding's whole value — refused, bind it first
// base e07e6e35 (#1720 on main): accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #600: `: W w @ W { ( make ) }`: a literal's field, not the binding's whole value — refused, bind it first
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

: W { Tk t }

@ main → i {
    : W w @ W { ( make ) }
    ( vec_clear [String] . . w t arena )
    ( nurl_println ( vec_at [s] . . w t idx 0 ) )
    ^ 0
}
