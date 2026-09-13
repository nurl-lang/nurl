$ `stdlib/core/vec.nu`

@ early b leave → i {
    : ( Vec i ) values ( vec_new [i] )
    ; { ( vec_free [i] values ) }
    ( vec_push [i] values 42 )
    ? leave { ^ ( vec_len [i] values ) } {}
    ( vec_push [i] values 7 )
    ^ ( vec_len [i] values )
}

@ falloff → v {
    : ( Vec i ) values ( vec_new [i] )
    ; { ( vec_free [i] values ) }
    ; { ( nurl_println_int ( vec_len [i] values ) ) }
    ( vec_push [i] values 4 )
}

@ main → i {
    ( nurl_println_int ( early T ) )
    ( nurl_println_int ( early F ) )
    ( falloff )
    ^ 0
}
