// A closure that pushes onto a captured Vec runs while a slice of that Vec is held: the push may move the buffer the slice reads.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( @ v i ) add \ i k → v { ( vec_push [i] v k ) }
    : ( Slice i ) s ( slice_from_vec [i] v )
    ( add 3 )
    ( nurl_println_int ( slice_len [i] s ) )
    ^ 0
}
