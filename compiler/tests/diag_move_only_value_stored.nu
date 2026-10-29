// diag_move_only_value_stored.nu — a value that is moved and never copied
// (a user `% Drop` type, a trait object) stored into an owner (agora
// #157): a struct literal, a field, a container a call keeps it in. Its
// old name is gone from there on, as it is for a String.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mkr → Res {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 7 )
    ^ @ Res { b }
}

: Box1 { Res r i pad }

% Size [T] {
    @ size T self → i
}

% Size Res { @ size Res r → i { ^ ( vec_len [i] . r buf ) } }

@ stored_twice → v {
    : Res a ( mkr )
    : Box1 h @ Box1 { a 0 }
    : Box1 h2 @ Box1 { a 1 }
}

@ read_after_its_vec_freed → v {
    : ( Vec Res ) v ( vec_new [Res] )
    : Res a ( mkr )
    ( vec_push [Res] v a )
    ( vec_free [Res] v )
    ( nurl_println_int ( vec_len [i] . a buf ) )
}

@ read_after_its_field_replaced → v {
    : Res a ( mkr )
    : ~ Box1 h @ Box1 { ( mkr ) 0 }
    = . h r a
    = . h r ( mkr )
    ( nurl_println_int ( vec_len [i] . a buf ) )
}

@ trait_object_after_its_vec_freed → v {
    : ( Vec % Size ) v ( vec_new [% Size] )
    : %Size d ( dyn Size ( mkr ) )
    ( vec_push [% Size] v d )
    ( vec_free [% Size] v )
    ( nurl_println_int ( size d ) )
}

@ main → i { ^ 0 }
