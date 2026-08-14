// borrow_strict_generic_maybe_double_free.nu — the conditional
// double-free (docs/MEMORY.md §6.2/§6.5) reached through a GENERIC
// wrapper instead of a second `vec_free` at the same site.
//
// `xs` is freed on one arm of a `?` and then handed to `dispose`,
// which frees it again: a real double-free on the path where the first
// free ran (confirmed under ASan — SEGV inside free from vec_free via
// dispose). Both halves had to work for this to be caught:
//
//   * the generic template's auto-sink summary, so `( dispose [i] xs )`
//     counts as a consume at all — without it the call was invisible
//     to the checker and even the UNCONDITIONAL double free through a
//     generic wrapper compiled clean (borrow_generic_sink_wrapper);
//   * the strict-mode rule that consuming a MAYBE-moved binding is an
//     error, which is what makes the conditional shape reportable.
//
// Strict-only, like borrow_strict_maybe_double_free: the default
// checker deliberately keeps the no-false-positive property and lets
// the conditional shape through.
//
// One positive + one rebind control.

$ `stdlib/core/vec.nu`

@ dispose [T] ( Vec T ) xs → v {
    ( vec_free [T] xs )
}

@ main → i {
    // POSITIVE — freed when the condition held, then consumed again by
    // the generic wrapper.
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 123 )
    : i n ( vec_len [i] xs )
    ? > n 0 { ( vec_free [i] xs ) } {}
    ( dispose [i] xs )

    // CONTROL — conditionally freed but REBOUND before the wrapper
    // call, so the binding is Owned again and must NOT be flagged.
    : ~ ( Vec i ) ys ( vec_new [i] )
    ( vec_push [i] ys 4 )
    ? > n 0 { ( vec_free [i] ys ) = ys ( vec_new [i] ) } {}
    ( dispose [i] ys )

    ^ 0
}
