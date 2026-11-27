// A struct holding a Vec: an element of the field read by index, the field measured and sliced.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: B { ( Vec i ) items i k }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    : B b @ B { v 0 }
    : i e ( vec_at [i] . b items . b k )
    : ( Slice i ) s ( slice_from_vec [i] . b items )
    ^ + e ( slice_len [i] s )
}
