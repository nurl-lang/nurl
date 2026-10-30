// in_param_beside_growing_closure: a Vec handed to an `in` parameter beside a closure that grows it: the callee viewed its parameter, ran the closure (which moved the Vec's buffer) and read the view. ASan: heap-use-after-free.
// Closed: a closure that runs at a call — handed to it, or the closure value called — is a route to every binding it captured: when what its body passes a capture to may move that capture's buffer or drop its elements (by the callee's final summaries), no other argument of the call may reach the capture (the binding itself, a view or a borrow of it, a closure that captured it). The exclusive-call check of the borrow walk (`clox`, bck_clo_route_check).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h275 | Vec passed `in` beside a closure growing it
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
    ( f v grow )
    ^ 0
}
