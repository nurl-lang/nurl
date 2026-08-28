// benchmark-contract: branch-lcg32;seed=123456789;iterations=25000000;threshold=2147483648
//
// packet_classifier — 25M iterations that pick one of two LCGs based on
// the current state. The branch is data-dependent and ~50/50, so this is
// the branch-misprediction shape of the set: same work per iteration as
// stream_lcg, but the predictor cannot learn the pattern.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else. `bench/bench.sh` gates
// on all five language implementations printing the same line before it
// reports a single timing number for the row.

@ main → i {
    : u64 iterations 25000000
    : u64 threshold 2147483648
    : ~ u64 state 123456789
    : ~ u64 k 0

    ~ < k iterations {
        ? < state threshold
        { = state & + * state 1664525 1013904223 0xffffffff }
        { = state & + * state 22695477 1 0xffffffff }
        = k + k 1
    }

    ( nurl_println_int # i & state 0x7fffffffffffffff )
    ^ 0
}
