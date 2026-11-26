// A closure pushes onto a Vec it captured while a view of an element read before is still read after (the checker refuses it).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    : ( @ v i ) add \ i k → v { ( vec_push [i] v k ) }
    ( add 2 )
    ^ ( slice_len [i] s )
}
