// borrow_strict_maybe_double_free.nu — strict-mode check for the
// CONDITIONAL double-free (the "maybe-moved hole", docs/MEMORY.md
// §6.2/§6.5).
//
// A value freed on only one arm of a `?` and then freed again is a real
// double-free on the path where the first free ran. The DEFAULT checker
// deliberately does not flag it — that keeps the no-false-positive
// property exact, at the price of this hole. `--strict-borrowck` closes
// it: consuming a MAYBE-moved binding is an error.
//
// This file compiles cleanly under the default checker and only errors
// under --strict-borrowck (which the test runner adds for borrow_strict_*).
//
// One positive case + one rebind control + one join-revive control.

$ `stdlib/core/vec.nu`

@ use_len i n → v {
    ? > n 100 { ( nurl_print `big
` ) } {}
}

@ main → i {
    // POSITIVE — freed when the condition held, then freed again
    // unconditionally: double-free whenever n > 2.
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    : i n ( vec_len [i] xs )
    ? > n 2 { ( vec_free [i] xs ) } {}
    ( vec_free [i] xs )

    // CONTROL 1 — conditionally freed but REBOUND before the second
    // free: the rebind revives the binding to Owned, so the second
    // free is fine and must NOT be flagged.
    : ~ ( Vec i ) ys ( vec_new [i] )
    ( vec_push [i] ys 2 )
    ? > n 2 { ( vec_free [i] ys ) = ys ( vec_new [i] ) } {}
    ( vec_free [i] ys )

    // CONTROL 2 — freed on BOTH arms then never touched again: the
    // joined state is moved, but with no further consume there is
    // nothing to flag under this rule.
    : ( Vec i ) zs ( vec_new [i] )
    ? > n 2 { ( vec_free [i] zs ) } { ( vec_free [i] zs ) }

    ( use_len n )
    ^ 0
}
