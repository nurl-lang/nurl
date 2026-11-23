// A function hands back a closure over its Vec parameter, a copy of the argument's handle; the caller releases the argument, then calls the closure.
$ `stdlib/core/vec.nu`

@ mk_len ( Vec i ) v → ( @ i ) { ^ \ → i { ^ ( vec_len [i] v ) } }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ i ) f ( mk_len v )
    ( vec_free [i] v )
    ( nurl_println_int ( f ) )
    ^ 0
}
