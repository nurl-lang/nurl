$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_reserve [i] v 64 )
    ( vec_push [i] v 1 )
    ( vec_shrink_to_fit [i] v )
    ^ ( vec_len [i] v )
}
