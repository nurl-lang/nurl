// H34: a sub-slice (slice_sub) is read after its Vec is freed.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 ) ( vec_push [i] v 8 ) ( vec_push [i] v 9 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    : ?( Slice i ) so ( slice_sub [i] s 1 3 )
    ( vec_free [i] v )
    ?? so { T sub → { ?? ( slice_get [i] sub 0 ) { T x → { ( nurl_println_int x ) } F → {} } } F → {} }
    ^ 0
}
