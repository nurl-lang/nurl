// A slice of a Vec read after the Vec was cut back (the checker refuses it).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    ( vec_truncate [i] v 1 )
    ^ ( slice_len [i] s )
}
