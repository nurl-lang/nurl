// A closure with no captures that takes a Vec and reads it.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( @ i ( Vec i ) ) count \ ( Vec i ) v → i { ^ ( vec_len [i] v ) }
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 1 )
    ( vec_push [i] w 2 )
    : i n ( count w )
    ^ + n ( vec_len [i] w )
}
