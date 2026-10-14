// A field that cannot be copied cannot be moved out of a struct that still
// drops it (h229).
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

@ eat sink Res r → v {
}

@ main → i {
    : Hold h @ Hold { @ Res { ( vec_new [i] ) } 1 }
    ( eat . h r )
    ^ 0
}
