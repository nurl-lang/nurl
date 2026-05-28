// borrow_aliased_mut.nu — N-readers-XOR-1-writer check at call sites.
//
// A binding passed to a call as `inout` is mutably borrowed for that
// call; it must be the exclusive path to the value at the call site.
// Passing the same binding as another argument of the SAME call —
// whether a second `inout` or a plain by-value read — aliases a
// mutable borrow and is flagged.
//
// The harness compiles `borrow_*` tests with --borrowck and records
// the diagnostics in the baseline.
//
// Two positive cases (both warn) + one negative control (no warning).

: Counter { i n  i max }

@ swap_counters inout Counter a  inout Counter b → v {
    : i t . a n
    = . a n . b n
    = . b n t
}

@ bump_by_other inout Counter a  Counter b → v {
    = . a n + . a n . b n
}

@ main → i {
    : ~ Counter c @ Counter { 3 10 }
    : ~ Counter c2 @ Counter { 9 10 }

    // POSITIVE — `c` handed to both `inout` parameters of one call.
    ( swap_counters c c )

    // POSITIVE — `c` is `inout` (mutable borrow) and also the plain
    // by-value argument of the same call.
    ( bump_by_other c c )

    // CONTROL — two distinct bindings; no aliasing, no warning.
    ( swap_counters c c2 )

    ^ 0
}
