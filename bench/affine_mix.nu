// benchmark-contract: affine-mix-xs9;seed=123456789;iterations=20000000;mask=0x03ffffffffffffff;xorshift=9
//
// affine_mix — 20M rounds of two affine steps over a 58-bit state with
// a xorshift mix between them. The mask makes each shift-add step
// affine mod 2^58, and LLVM's unroller composes chained affine steps
// into one, so without the xor this row measured the compiler's
// composition factor rather than the chain. The xor of a shifted copy
// breaks affinity: every step's shifts, adds, masks and xor stay on the
// critical path, all of it in the integer ALU.
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
        = state ^^ state >> state 9
        = state & - << state 2 3 mask
        = k + k 1
    }

    ( nurl_print_int # i & state 0x7fffffffffffffff )
    ^ 0
}
