$ `stdlib/core/vec.nu`

@ eat sink ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ main → i {
    : i c 1
    : ( @ i i ) f \ i x → i { ^ + x c }
    : ( Vec i ) w ( vec_new [i] )
    ( vec_push [i] w 1 )
    : i n ( eat w )
    ^ + n ( f ( vec_len [i] w ) )
}
