// H43: a Slice is read after its Vec was handed to a sink parameter.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ eat sink ( Vec i ) v → v { ( vec_free [i] v ) }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    ( eat v )
    ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
