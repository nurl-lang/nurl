// Borrow checker — loop-carried double-free regression (while loop).
// `xs` is declared OUTSIDE the loop and freed on every iteration. The
// first pass consumes it; the second pass re-reads (and re-frees) a
// moved-from binding — a guaranteed double-free once the loop runs
// more than once. The checker re-walks the body seeded with the
// loop's back-edge state, so the free of `xs` is flagged.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    : ~ i k 0
    ~ < k 3 {
        ( vec_free [i] xs )
        = k + k 1
    }
    ^ 0
}
