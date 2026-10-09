// H53: safe code writes a Slice's len field past its buffer.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ~ ( Slice i ) s ( slice_from_vec [i] v )
    = . s len 100000
    ?? ( slice_get [i] s 99999 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
