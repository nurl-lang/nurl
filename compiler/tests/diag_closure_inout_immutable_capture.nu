// diag_closure_inout_immutable_capture.nu — a closure cannot hand an
// immutable binding it captured to an `inout` parameter: the capture is a
// snapshot as immutable as the binding (h298).

$ `stdlib/core/vec.nu`

@ bump inout i n → v { = n + n 1 }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    : i n 0
    ( vec_each [i] xs \ i x → v { ( bump n ) } )
    ( nurl_println_int n )
    ^ 0
}
