$ `stdlib/core/vec.nu`

: S { ( Vec i ) v i n }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    : S s @ S { v 1 }
    ( vec_push [i] v 2 )
    ^ 0
}
