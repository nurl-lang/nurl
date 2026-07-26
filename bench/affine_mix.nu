// benchmark-contract: affine-mix;seed=123456789;iterations=20000000;mask=0x03ffffffffffffff
//
// affine_mix — 20M rounds of two chained affine steps over a 58-bit
// state. Every step depends on the previous one, so the loop cannot be
// folded into a closed form; the shifts keep the mix in the integer ALU.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else. `bench/bench.sh` gates
// on all five language implementations printing the same line before it
// reports a single timing number for the row.

@ main → i {
    : u64 iterations 20000000
    : u64 mask 0x03ffffffffffffff
    : ~ u64 state 123456789
    : ~ u64 k 0

    ~ < k iterations {
        = state & + << state 3 k mask
        = state & - << state 2 3 mask
        = k + k 1
    }

    ( nurl_print_int # i & state 0x7fffffffffffffff )
    ^ 0
}
