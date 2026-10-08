// H89: a view of a view call's result (slice_sub of slice_from_vec); the Vec is freed; the view is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 ) ( vec_push [i] v 8 )
    : ?( Slice i ) o ( slice_sub [i] ( slice_from_vec [i] v ) 0 1 )
    ( vec_free [i] v )
    ?? o { T s → { ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} } } F → {} }
    ^ 0
}
