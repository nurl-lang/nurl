$ `stdlib/core/vec.nu`

: Bag { ( Vec i ) items i n }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    : Bag b @ Bag { v 1 }
    ( nurl_println_int ( vec_len [i] . b items ) )
    ^ + ( vec_len [i] . b items ) . b n
}
