$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ~ i acc 0
    ~ x v { ( vec_push [i] v x ) }
    ^ acc
}
