// A Vec moved into an option, then pushed (the checker refuses it).
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    : ?( Vec i ) o @ ?( Vec i ) { T v }
    ( vec_push [i] v 2 )
    ?? o { T w → { ^ ( vec_len [i] w ) } F → { ^ 0 } }
}
