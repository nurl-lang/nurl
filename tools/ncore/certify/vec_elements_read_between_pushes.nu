$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : i a ( vec_at [i] v 0 )
    ( vec_push [i] v a )
    ^ + a ( vec_at [i] v 1 )
}
