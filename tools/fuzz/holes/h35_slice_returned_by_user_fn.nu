// H35: a user function returns a Slice of its parameter; the Vec is freed; the Slice is read.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ view ( Vec i ) v → ( Slice i ) { ^ ( slice_from_vec [i] v ) }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Slice i ) s ( view v )
    ( vec_free [i] v )
    ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
