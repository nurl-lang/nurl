// closure_called_with_growing_closure: a closure holding a view of the Vec it captured, called directly with a closure that grows that Vec as its argument: the called closure ran its argument while its view was live. ASan: heap-use-after-free.
// Closed: a closure that runs at a call — handed to it, or the closure value called — is a route to every binding it captured: when what its body passes a capture to may move that capture's buffer or drop its elements (by the callee's final summaries), no other argument of the call may reach the capture (the binding itself, a view or a borrow of it, a closure that captured it). The exclusive-call check of the borrow walk (`clox`, bck_clo_route_check).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h276 | closure holding a view of its capture called with the closure that grows it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( @ v ) grow \ → v {
        : ~ i k 0
        ~ < k 1000 { ( vec_push [i] v k ) = k + k 1 }
    }
    : ( @ v ( @ v ) ) use \ ( @ v ) g → v {
        : ( Slice i ) s ( slice_from_vec [i] v )
        ( g )
        ( nurl_println_int ( slice_at [i] s 0 ) )
    }
    ( use grow )
    ^ 0
}
