// self_viewing_struct_returned_by_a_callee_then_its_arena_cleared: agora #600 — `: Tk t ( make )`, make's answer `.^arena`, then `( vec_clear . t arena )` and a read of `. t idx` (formal's a01 against #1714)
// base 3c05d83d (#1720): accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #600: `: Tk t ( make )`, make's answer `.^arena`, then `( vec_clear . t arena )` and a read of `. t idx` (formal's a01 against #1714)
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
    ( vec_clear [String] . t arena )
    ( nurl_println ( vec_at [s] . t idx 0 ) )
    ^ 0
}
