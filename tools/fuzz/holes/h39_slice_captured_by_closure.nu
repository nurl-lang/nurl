// H39: a closure captures a Slice; the Vec is freed; the closure runs.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    : ( @ i ) f \ → i { ^ ?? ( slice_get [i] s 0 ) { T x → x F → 0 } }
    ( vec_free [i] v )
    ( nurl_println_int ( f ) )
    ^ 0
}
