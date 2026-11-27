// A struct's Vec field cut back to a length read from the struct.
$ `stdlib/core/vec.nu`

: B { ( Vec i ) items i k }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    : B b @ B { v 1 }
    ( vec_truncate [i] . b items . b k )
    ^ ( vec_len [i] . b items )
}
