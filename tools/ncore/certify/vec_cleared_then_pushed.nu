$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_clear [i] v )
    ( vec_push [i] v 2 )
    : ~ String s ( string_from `ab` )
    ( string_push_str s `cd` )
    : ( Vec i ) w v
    : i n ( vec_len [i] w )
    ( vec_free [i] w )
    ^ + n ( string_len s )
}
