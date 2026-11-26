// A Vec handed `inout` to a function that pushes to it.
$ `stdlib/core/vec.nu`

@ add_two inout ( Vec i ) v → v {
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
}

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( add_two v )
    ( add_two v )
    ^ ( vec_len [i] v )
}
