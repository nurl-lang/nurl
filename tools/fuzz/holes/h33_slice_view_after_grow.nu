// H33: a Slice of a Vec is read after the Vec grew (vec_push reallocates).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] v k ) = k + k 1 }
    ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
