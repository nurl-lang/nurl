// benchmark-contract: binary-search;seed=123456789;queries=5000000;values=even-0..126;algorithm=lower-bound
//
// binary_search — 5M lower-bound searches over a 64-entry sorted table of
// the even numbers 0..126, with LCG-drawn targets in 0..127 (so about
// half the queries hit). Six dependent, unpredictable iterations per
// query: the load address of step n+1 depends on the comparison at step
// n, which is the pointer-chasing shape.
//
// The table is `malloc`ed and filled with `values[i] = 2 * i` — the same
// contents the C and Rust peers spell out as a literal array.
//
// The `low < 64 && values[low] == target` guard is written as two nested
// `?`s: NURL's `&` on booleans does not short-circuit, so a single `&`
// would read `values[64]` — one past the end — whenever the lower bound
// lands at the end of the table.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else. `bench/bench.sh` gates
// on all five language implementations printing the same line before it
// reports a single timing number for the row.

@ main → i {
    : i n 64
    : u64 iterations 5000000
    : *u64 values # *u64 ( malloc * n 8 )
    : ~ i z 0
    ~ < z n {
        = . values z # u64 * 2 z
        = z + z 1
    }

    : ~ u64 state 123456789
    : ~ u64 hits 0
    : ~ u64 k 0

    ~ < k iterations {
        = state & + * state 1664525 1013904223 0xffffffff
        : u64 target & state 127

        : ~ i low 0
        : ~ i high n
        ~ < low high {
            : i middle + low >> - high low 1
            ? < . values middle target
            { = low + middle 1 }
            { = high middle }
        }

        ? < low n {
            ? == . values low target { = hits + hits 1 } {}
        } {}

        = k + k 1
    }

    : u64 checksum ^^ state hits
    ( free values )
    ( nurl_println_int # i & checksum 0x7fffffffffffffff )
    ^ 0
}
