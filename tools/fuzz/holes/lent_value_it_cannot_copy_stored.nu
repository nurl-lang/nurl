// lent_value_it_cannot_copy_stored: a call's result that only lends and cannot be copied — `( vec_at v 0 )` of a `( Vec Res )` — stored where it is kept: pushed into another Vec, or into a struct literal. Both owners released it. A String is copied into such a place; this one cannot be.
// Closed: decided at module end, on the lending call's final summary (a generic instance is compiled late): a lent value that cannot be copied handed to a parameter its callee keeps or releases, or into a literal, is rejected.
// main (before this PR): ASan heap-use-after-free.
// map: §2.12 | A2 | rejected | h230 | lent %Drop element stored into struct literal: two owners
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
