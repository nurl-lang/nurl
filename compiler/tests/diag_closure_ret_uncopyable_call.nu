// A closure handing back what a call lent (`vec_at` lends an element)
// would give its caller a value the vector still owns; one that cannot be
// copied is rejected on the callee's final summary, at module end (h219).
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ main → i {
    : ( Vec Res ) rs ( vec_new [Res] )
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    ( vec_push [Res] rs @ Res { v } )
    : ( @ Res ) f \ → Res { ( vec_at [Res] rs 0 ) }
    : Res a ( f )
    ( nurl_println_int ( vec_len [i] . a buf ) )
    ^ 0
}
