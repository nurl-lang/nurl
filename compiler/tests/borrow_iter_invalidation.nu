// borrow_iter_invalidation.nu — BORROW.md Phase 6.
// A `~ x xs { ... }` foreach loop borrows the container `xs` for the
// body's duration: gen_foreach snapshots the buffer pointer + length
// once, up front. Mutating `xs` inside the body — `vec_push` (which
// may realloc), `vec_set`, `vec_free`, or any other container
// mutator — leaves the loop's cursor pointing at a stale or freed
// buffer. The borrow checker rejects mutating the iterated container
// from inside the loop.
//
// The harness compiles `borrow_*` tests with --borrowck and records
// the diagnostics in the baseline.
//
// Two positive cases (both warn) + two negative controls (no warning).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ( Vec i ) ws ( vec_new [i] )

    // POSITIVE — pushing into `xs` while iterating it can realloc the
    // backing buffer out from under the loop cursor.
    ~ x xs {
        ( vec_push [i] xs x )
    }

    // POSITIVE — rewriting an element of `xs` mid-iteration.
    ~ x2 xs {
        : b _ok ( vec_set [i] xs 0 x2 )
    }

    // CONTROL — the loop iterates `xs` but mutates a *different*
    // container `ws`; the cursor over `xs` is untouched.
    ~ y xs {
        ( vec_push [i] ws y )
    }

    // CONTROL — mutating `xs` AFTER the loop has finished is fine.
    ( vec_push [i] xs 99 )

    ( vec_free [i] ws )
    ( vec_free [i] xs )
    ^ 0
}
