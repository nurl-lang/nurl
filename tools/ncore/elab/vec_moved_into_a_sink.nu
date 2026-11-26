// A Vec moved into a function that takes it over.
$ `stdlib/core/vec.nu`

@ total sink ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 4 )
    ( vec_push [i] v 5 )
    ^ ( total v )
}
