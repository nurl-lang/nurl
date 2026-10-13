// A call's result that only lends and cannot be copied cannot be stored
// where it is kept — into a literal here (h230): the Vec still owns it.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

@ main → i {
    : ( Vec Res ) v ( vec_new [Res] )
    ( vec_push [Res] v @ Res { ( vec_new [i] ) } )
    : Hold h @ Hold { ( vec_at [Res] v 0 ) 1 }
    ^ 0
}
