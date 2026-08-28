// benchmark-contract: histogram-xs13;seed=123456789;iterations=20000000;bins=64;index=state&63;xorshift=13
//
// histogram_bins — 20M LCG steps, each incrementing one of 64 bins at a
// data-dependent index, then a weighted XOR fold of the bins. The
// read-modify-write at an unpredictable index is the point: consecutive
// iterations frequently hit the same cache line, so store-to-load
// forwarding dominates.
//
// The set is named `histogram_bins` rather than `histogram` because
// `bench/histogram.{nu,py,rs,js}` is an unrelated, older benchmark
// (highest single-digit count in a string).
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else. `bench/bench.sh` gates
// on all five language implementations printing the same line before it
// reports a single timing number for the row.

@ main → i {
    : i bin_count 64
    : u64 iterations 20000000
    : *u64 bins # *u64 ( malloc * bin_count 8 )
    : ~ i z 0
    ~ < z bin_count {
        = . bins z # u64 0
        = z + z 1
    }

    : ~ u64 state 123456789
    : ~ u64 k 0
    ~ < k iterations {
        = state & + * state 1664525 1013904223 0xffffffff
        = state ^^ state >> state 13
        : u64 index & state 63
        = . bins index + . bins index # u64 1
        = k + k 1
    }

    : ~ u64 checksum state
    : ~ i slot 0
    ~ < slot bin_count {
        = checksum ^^ checksum * . bins slot # u64 + slot 1
        = slot + slot 1
    }

    ( free bins )
    ( nurl_println_int # i & checksum 0x7fffffffffffffff )
    ^ 0
}
