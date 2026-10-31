// nested_growing_closure_beside_vec: a closure that runs a growing closure, handed to a function beside the Vec they grow: the callee viewed its parameter, ran the closure and read the view. ASan: heap-use-after-free.
// Closed: by h278 the outer closure carries the inner one's effect, and by h274 a closure that changes a capture may not be handed to a call beside another argument that reaches it.
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h280 | closure that runs a growing captured closure handed to a call beside the Vec
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f ( Vec i ) w ( @ v ) g → v {
    : ( Slice i ) s ( slice_from_vec [i] w )
    ( g )
    ( nurl_println_int ( slice_at [i] s 0 ) )
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( @ v ) grow \ → v {
        : ~ i k 0
        ~ < k 1000 { ( vec_push [i] v k ) = k + k 1 }
    }
    : ( @ v ) outer \ → v { ( grow ) }
    ( f v outer )
    ^ 0
}
