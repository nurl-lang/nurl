// A `sink` parameter is the function's own: it is dropped on the way out,
// so a view of it handed back dangles (h225).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ view_of sink ( Vec i ) v → ( Slice i ) {
    ^ ( slice_from_vec [i] v )
}

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    : ( Slice i ) s ( view_of a )
    ^ 0
}
