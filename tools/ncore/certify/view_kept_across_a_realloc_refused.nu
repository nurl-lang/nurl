$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    ( vec_push [i] v 2 )
    ^ ( slice_len [i] s )
}
