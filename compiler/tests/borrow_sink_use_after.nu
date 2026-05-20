// borrow_sink_use_after.nu — BORROW.md Phase 4: a `sink` parameter
// consumes its argument. Once a binding is handed to a `sink`
// parameter the caller has given up ownership; using it afterwards
// is a use-after-move. The borrow checker records the `sink`
// argument as moved, so a later read is flagged exactly like a use
// after a `*_free` destructor.
//
// The harness compiles `borrow_*` tests with --borrowck and records
// the diagnostic in the baseline.
//
// One positive case (warns) + one negative control (no warning).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ give_away sink ( Vec i ) g → v {
    ( vec_free [i] g )
}

@ main → i {
    // POSITIVE — `xs` is consumed by `give_away`, then read again.
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( give_away xs )
    : i n ( vec_len [i] xs )
    ( nurl_print ( nurl_str_int n ) )

    // CONTROL — `ys` is consumed and never touched afterwards.
    : ( Vec i ) ys ( vec_new [i] )
    ( vec_push [i] ys 2 )
    ( give_away ys )

    ^ 0
}
