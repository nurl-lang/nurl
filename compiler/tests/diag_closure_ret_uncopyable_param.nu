// A closure only borrows its parameters (its caller keeps them), so one
// that cannot be copied cannot be handed back as the caller's own (h219) —
// with `^` or as the body's final value alike.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    : Res r @ Res { v }
    : ( @ Res Res ) f \ Res p → Res { ^ p }
    : Res a ( f r )
    ( nurl_println_int ( vec_len [i] . a buf ) )
    ^ 0
}
