// benchmark-contract: ring-write;seed=123456789;iterations=20000000;words=64;value=state32x2
//
// ring_write — 20M LCG steps, each storing a 64-bit word into a 64-slot
// ring buffer. Same arithmetic as stream_lcg plus one dependent store
// per iteration, so the store pipeline and the address computation are
// what separate the languages.
//
// NURL has no fixed-size stack array: the ring lives in a `malloc`ed
// `*u64` block, where the C and Rust peers use `uint64_t buf[64]` /
// `[u64; 64]` on the stack.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else. `bench/bench.sh` gates
// on all five language implementations printing the same line before it
// reports a single timing number for the row.

@ main → i {
    : i words 64
    : u64 iterations 20000000
    : *u64 buf # *u64 ( malloc * words 8 )
    : ~ i z 0
    ~ < z words {
        = . buf z # u64 0
        = z + z 1
    }

    : ~ u64 state 123456789
    : ~ u64 k 0
    ~ < k iterations {
        = state & + * state 1664525 1013904223 0xffffffff
        = . buf & k 63 | << state 32 state
        = k + k 1
    }

    : u64 result ^^ | << state 32 state . buf 0
    ( free buf )
    ( nurl_print_int # i & result 0x7fffffffffffffff )
    ^ 0
}
