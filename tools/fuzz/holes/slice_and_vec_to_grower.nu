// slice_and_vec_to_grower: a Slice and its Vec handed to one function that grows the Vec, then reads the Slice.
// map: CallT.args | A1 | rejected | h63 | Slice and its Vec passed to one fn that grows the Vec then reads Slice
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow_then_read ( Vec i ) v ( Slice i ) s → i {
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] v k ) = k + k 1 }
    ^ ?? ( slice_get [i] s 0 ) { T x → x F → 0 }
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    ( nurl_println_int ( grow_then_read v ( slice_from_vec [i] v ) ) )
    ^ 0
}
