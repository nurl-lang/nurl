// A field that cannot be copied, handed back out of a struct the function
// made, would be released with that struct on the way out (h221).
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

@ mk → Res {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    : Hold h @ Hold { @ Res { v } 1 }
    . h r
}

@ main → i {
    : Res a ( mk )
    ( nurl_println_int ( vec_len [i] . a buf ) )
    ^ 0
}
