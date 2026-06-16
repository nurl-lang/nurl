// Borrow checker — loop-carried double-free regression (foreach).
// The container `ys` drives the loop; `xs` is an OUTER binding freed
// in the body. Each iteration re-frees the already-moved `xs` — a
// loop-carried double-free. (Freeing the loop ELEMENT instead, as in
// the negative-control test loop_elem_free.nu, is legal and must NOT
// flag — the element is a fresh load each iteration.)
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    : ( Vec i ) ys ( vec_new [i] )
    ( vec_push [i] ys 7 )
    ~ y ys {
        ( vec_free [i] xs )
    }
    ( vec_free [i] ys )
    ^ 0
}
