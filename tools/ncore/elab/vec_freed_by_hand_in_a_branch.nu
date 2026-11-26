// A Vec released by vec_free on one branch.
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : i n ( vec_len [i] v )
    ? > n 0 { ( vec_free [i] v ) } {}
    ^ n
}
