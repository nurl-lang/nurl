$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) values ( vec_new [i] )
    ; { ( nurl_println_int ( vec_len [i] values ) ) }
    ( vec_free [i] values )
    ^ 0
}
