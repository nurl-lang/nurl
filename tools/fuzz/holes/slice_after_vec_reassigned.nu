// slice_after_vec_reassigned: a Slice is read after its Vec binding is given a new value.
// map: StmtT.assign | A1 | rejected | h42 | Slice read after its Vec binding is reassigned
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    = v ( vec_new [i] )
    ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
