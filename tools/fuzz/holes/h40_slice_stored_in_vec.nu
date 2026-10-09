// H40: a Slice is pushed into a Vec of Slices; the source Vec is freed; the element is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Vec ( Slice i ) ) ss ( vec_new [( Slice i )] )
    ( vec_push [( Slice i )] ss ( slice_from_vec [i] v ) )
    ( vec_free [i] v )
    ?? ( vec_get [( Slice i )] ss 0 ) { T s → { ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} } } F → {} }
    ^ 0
}
