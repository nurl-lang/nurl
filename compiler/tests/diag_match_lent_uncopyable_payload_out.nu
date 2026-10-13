// A payload the arm only borrows — an option a struct field keeps — that
// cannot be copied cannot be handed to the binding a match initialises
// (h227): the struct still drops it.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Holder { ? Res o i n }

@ main → i {
    : Holder h @ Holder { @ ?Res { T @ Res { ( vec_new [i] ) } } 1 }
    : Res q ?? . h o { T r → { r } F _ → { @ Res { ( vec_new [i] ) } } }
    ^ 0
}
