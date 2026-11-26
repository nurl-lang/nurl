// A closure reads a Vec it captured, and the Vec is read after the call: a capture by name, read only.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : ( @ i i ) f \ i k → i { ^ ( vec_at [i] v k ) }
    : i a ( f 0 )
    ^ + a ( vec_len [i] v )
}
