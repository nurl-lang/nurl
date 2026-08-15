// diag_foreach_mutate_one_call_deep.nu — mutating an iterated container
// through a helper function.
//
// (Named "one_call_deep", not "via_helper": test_skips.sh skips any test
// whose name ends in `_mod`, `_helper` or `_lib` as an importable
// module with no main(), so the `_helper` spelling made this file
// silently never run — it showed up only as the SKIP count moving.)
//
// A `~ x xs` foreach holds a borrow of xs (docs/MEMORY.md §2.5), and the
// direct `( vec_push xs … )` inside the body has warned for a long time.
// The same push one call away did not, which reads as "wrap it in a
// function" being a cure for a borrow violation. A per-function summary
// (`g_fn_mutates`) records which parameters' containers a body mutates,
// inferred in codegen order like the sink / escape / arc summaries, and
// the call site consults it.
//
// Rejected, matching the direct case exactly — the point is that both
// spellings of one thing now get one answer.
//
// Measured, this shape is not memory-unsafe today: a Vec is a handle to
// a control block and the loop reads through it, so a forced realloc
// mid-iteration does not dangle, and both spellings return the correct
// sum. §2.5 is a conservative guard, which is why tools/metamorph ranks
// a gap here below anything that corrupts memory — but a guard that
// applies to one spelling and not its twin teaches the wrong cure.

$ `stdlib/core/vec.nu`

@ grow ( Vec i ) v → v { ( vec_push [i] v 2 ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ~ y xs { ( grow xs ) }
    ( vec_free [i] xs )
    ^ 0
}
