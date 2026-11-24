$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Vec i ) w v
    : i a ( vec_at [i] v 0 )
    ^ + a ( vec_len [i] w )
}
