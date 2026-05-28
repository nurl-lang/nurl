// borrow_escape_assign.nu — region tracking + copy propagation in the
// escape analysis. Two shapes a name+flag heuristic alone would miss:
//
//   * `= outer inner` — a closure created in an inner block, capturing
//     an inner-block `: ~` binding, assigned to a binding declared in
//     a SHALLOWER (longer-lived) scope. The reference outlives its
//     referent the moment the inner block exits. The old hack had no
//     gen_assign check at all; the region check (declaration depth of
//     the LHS vs. referent depth of the RHS) catches it.
//
//   * `: (@ v) b a` — copying a stack-reference binding. The old hack
//     only tagged closures at their literal; a copy lost the taint, so
//     `^ b` escaped silently. Stack-reference-ness now propagates
//     through the copy via the source binding's `__refdepth`.
//
// The harness compiles `borrow_*` tests with --borrowck and records
// the diagnostics in the baseline.
//
// Two positive cases (both warn) + one negative control (no warning).

: Counter { i n  i max }

// POSITIVE — closure captures a `~`-loop-local `c` (region depth 3:
// fn body / loop body), then is assigned to `holder`, declared at the
// function body (depth 1). After the loop, `holder` dangles.
@ leak_via_assign → i {
    : ~ ( @ v ) holder \ → v {}
    : ~ i k 0
    ~ < k 1 {
        : ~ Counter c @ Counter { 0 10 }
        : ( @ v ) bump \ → v { = . c n + . c n 1 }
        = holder bump
        = k + k 1
    }
    ( holder )
    ^ 0
}

// POSITIVE — `alias` is a plain copy of the byref-capturing closure
// `bump`; returning the copy dangles exactly as returning `bump` would.
@ leak_via_copy → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) bump \ → v { = . c n + . c n 1 }
    : ( @ v ) alias bump
    ^ alias
}

// CONTROL — closure and the binding it is assigned into share the
// same region (function body, depth 1). No reference outlives its
// referent, so no warning must fire.
@ no_escape_same_region → i {
    : ~ Counter c @ Counter { 0 10 }
    : ~ ( @ v ) h \ → v {}
    : ( @ v ) bump \ → v { = . c n + . c n 1 }
    = h bump
    ( h )
    ^ . c n
}

@ main → i {
    : i _a ( leak_via_assign )
    : ( @ v ) _b ( leak_via_copy )
    : i _c ( no_escape_same_region )
    ^ 0
}
