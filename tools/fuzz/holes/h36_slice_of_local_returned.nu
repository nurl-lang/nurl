// H36: a function returns a Slice of its own local Vec, which is dropped at the return.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → ( Slice i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ^ ( slice_from_vec [i] v )
}

@ main → i {
    : ( Slice i ) s ( mk )
    ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
