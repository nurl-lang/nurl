// closure_view_beside_growing_closure: a closure that holds a view of the Vec it captured, handed to a function beside a closure that grows that Vec, called it while the view was live: inside the callee the two closures are unrelated names, so growing through one left the other's view dangling. ASan: heap-use-after-free.
// Closed: a closure that runs at a call — handed to it, or the closure value called — is a route to every binding it captured: when what its body passes a capture to may move that capture's buffer or drop its elements (by the callee's final summaries), no other argument of the call may reach the capture (the binding itself, a view or a borrow of it, a closure that captured it). The exclusive-call check of the borrow walk (`clox`, bck_clo_route_check).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h274 | closure holding a view of its capture handed to a call beside a closure growing it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ apply ( @ v ( @ v ) ) a ( @ v ) b → v { ( a b ) }

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
    ( apply use grow )
    ^ 0
}
