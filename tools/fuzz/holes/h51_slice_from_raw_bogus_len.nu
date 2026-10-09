// H51: slice_from_raw over a Vec's buffer with a length the buffer does not have.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Slice i ) s ( slice_from_raw [i] ( vec_data [i] v ) 100000 )
    ?? ( slice_get [i] s 99999 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
