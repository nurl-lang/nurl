// H98: a Vec's raw data pointer, passed where a string is expected, is read to a NUL its bytes do not have.
$ `stdlib/core/vec.nu`

@ show s x → v { ( nurl_println x ) }

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 65 )
    ( show ( vec_data [u] v ) )
    ^ 0
}
