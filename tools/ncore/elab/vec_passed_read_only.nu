// A Vec lent to a function that only reads it, then read again.
$ `stdlib/core/vec.nu`

@ count ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : i n ( count v )
    ^ + n ( vec_len [i] v )
}
