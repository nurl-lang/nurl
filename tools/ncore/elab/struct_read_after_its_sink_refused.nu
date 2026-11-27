// A struct holding a Vec handed to a sink, then its field read (the checker refuses it).
$ `stdlib/core/vec.nu`

: B { ( Vec i ) items i k }

@ take sink B b → i { ^ + . b k 0 }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    : B b @ B { v 0 }
    : i r ( take b )
    ^ + r ( vec_len [i] . b items )
}
