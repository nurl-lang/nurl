// A closure's caller takes its result as its own, and a value that cannot
// be copied (a `% Drop` value with no clone) can be handed over only by
// its owner (h219): the closure keeps its capture for its next call, so
// handing `r` back would release it twice.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    : Res r @ Res { v }
    : ( @ Res ) f \ → Res { r }
    : Res a ( f )
    ( nurl_println_int ( vec_len [i] . a buf ) )
    ^ 0
}
