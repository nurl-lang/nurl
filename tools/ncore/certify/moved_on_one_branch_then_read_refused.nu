$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ~ i n 0
    ? T { = n ( eat v ) } {}
    ^ + n ( vec_len [i] v )
}
