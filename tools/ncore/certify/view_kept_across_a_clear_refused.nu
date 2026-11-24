$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Slice i ) sl ( slice_from_vec [i] v )
    ( vec_clear [i] v )
    ^ ( slice_len [i] sl )
}
