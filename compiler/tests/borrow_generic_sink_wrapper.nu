// borrow_generic_sink_wrapper.nu — auto-sink inference through a
// GENERIC wrapper.
//
// A function that frees its parameter is a sink: its caller loses the
// binding. For an ordinary function the checker learns this while
// compiling the body (bck_record_inferred_sink → g_fn_sink). A generic
// body is not compiled where it is written — it is stored and
// instantiated later under a mangled name — so the summary reached
// neither the generic name nor any call site preceding the deferred
// instantiation, and this exact program compiled clean and
// double-freed at runtime while the identical non-generic wrapper was
// rejected. compute_generic_inout_sink now reads the template body.
//
// One positive (the second `dispose` is a use-after-move) plus a
// control: `borrow` takes the same parameter and does NOT free it, so
// reading `ys` after the call must stay legal.

$ `stdlib/core/vec.nu`

// Sink: consumes its argument.
@ dispose [T] ( Vec T ) xs → v {
    ( vec_free [T] xs )
}

// Borrow: reads its argument and leaves it to the caller.
@ peek [T] ( Vec T ) xs → i {
    ^ ( vec_len [T] xs )
}

@ main → i {
    // CONTROL — a generic that only READS its parameter is not a sink;
    // `ys` is still owned after the call and freeing it here is right.
    : ( Vec i ) ys ( vec_new [i] )
    ( vec_push [i] ys 7 )
    : i m ( peek [i] ys )
    ? > m 100 { ( nurl_print `big\n` ) } {}
    ( vec_free [i] ys )

    // POSITIVE — the first `dispose` consumes `xs`; the second one is
    // a double free of the same Vec.
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 123 )
    ( dispose [i] xs )
    ( dispose [i] xs )

    ^ 0
}
