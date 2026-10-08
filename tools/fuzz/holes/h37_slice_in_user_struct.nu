// H37: a Slice kept in a user struct; the Vec is freed; the Slice is read through the struct.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Rd { ( Slice i ) s i pos }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : Rd r @ Rd { ( slice_from_vec [i] v ) 0 }
    ( vec_free [i] v )
    ?? ( slice_get [i] . r s 0 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
