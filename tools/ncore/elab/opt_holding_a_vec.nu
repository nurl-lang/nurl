// An option holding a Vec: the Vec moved in, and lent out where the option is matched.
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 2 )
    : ?( Vec i ) o @ ?( Vec i ) { T v }
    ?? o { T w → { ^ ( vec_len [i] w ) } F → { ^ 0 } }
}
