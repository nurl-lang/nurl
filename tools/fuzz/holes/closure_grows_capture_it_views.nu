// closure_grows_capture_it_views: a closure that captured both a Vec and a view of it grew the Vec, then read the view: inside the body the two captures were unrelated names. ASan: heap-use-after-free.
// Closed: a closure whose body may move a capture's buffer or drop its elements may not also hold another capture that points into it or borrows from it — checked where the literal is made, with the final summaries (a `clox` row of the literal, bck_clo_route_check); a captured closure counts as each binding it captured.
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h279 | closure captured a Vec and a view of it, grows the one and reads the other
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( Slice i ) s ( slice_from_vec [i] v )
    : ( @ v ) both \ → v {
        : ~ i k 0
        ~ < k 1000 { ( vec_push [i] v k ) = k + k 1 }
        ( nurl_println_int ( slice_at [i] s 0 ) )
    }
    ( both )
    ^ 0
}
