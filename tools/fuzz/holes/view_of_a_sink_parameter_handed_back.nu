// view_of_a_sink_parameter_handed_back: a view of a `sink` parameter handed back — a Slice of the Vec it was given, a closure over a `% Drop` value it was given — passed the borrow walk as a view of storage its caller holds. The caller gave that value up: the function drops it on the way out, and the caller read freed memory. Only a raw-string `sink` counted as the function's own.
// Closed: every `sink` parameter the function drops is a binding of its frame to the walk; a view of it handed back is rejected like a view of a local.
// main (before this PR): ASan heap-use-after-free.
// map: FnOK | A1 | rejected | h225 | returns slice view of a sink param the function drops on exit
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ view_of sink ( Vec i ) v → ( Slice i ) {
    ^ ( slice_from_vec [i] v )
}

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 7 )
    : ( Slice i ) s ( view_of a )
    ?? ( slice_get [i] s 0 ) { T x → { ( nurl_println_int x ) } F _ → {} }
    ^ 0
}
