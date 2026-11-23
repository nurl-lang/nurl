$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    : ~ ( Vec i ) w v
    ( vec_push [i] v 1 )
    ^ ( vec_len [i] w )
}
