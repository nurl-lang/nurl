// H227: a match on an option a struct field keeps — `?? . h o { T r → { r } … }`, the payload a `% Drop` value with no clone — handed its payload to the binding the match initialised: the binding and the struct both released it.
// Closed: a payload the arm only borrows that cannot be copied cannot be handed to an owner — rejected; the struct keeps it (a field scrutinee is always lent, a local's too).
// main (before this PR): ASan heap-use-after-free.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Holder { ? Res o i n }

@ main → i {
    : Holder h @ Holder { @ ?Res { T @ Res { ( vec_new [i] ) } } 1 }
    : Res q ?? . h o { T r → { r } F _ → { @ Res { ( vec_new [i] ) } } }
    ( nurl_println_int ( vec_len [i] . q buf ) )
    ^ 0
}
