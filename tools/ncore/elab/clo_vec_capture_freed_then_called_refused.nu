// A closure reads a Vec it captured by name; the Vec is freed, then the closure runs (the checker refuses it).
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : ( @ i i ) f \ i k → i { ^ ( vec_at [i] v k ) }
    ( vec_free [i] v )
    ^ ( f 0 )
}
