// slice_literal_bogus_len: a Slice literal built in safe code with a length its buffer does not have.
// map: §6.2 | B | rejected | h52 | Slice literal forged in safe code with bogus length
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( Slice i ) s @ ( Slice i ) { ( vec_data [i] v ) 100000 }
    ?? ( slice_get [i] s 99999 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
