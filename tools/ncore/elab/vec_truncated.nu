// A Vec cut back to a length, then pushed to again.
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    ( vec_push [i] v 3 )
    : i keep 1
    ( vec_truncate [i] v keep )
    ( vec_push [i] v 4 )
    ( vec_truncate [i] v 0 )
    ^ ( vec_len [i] v )
}
