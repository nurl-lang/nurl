// benchmark-contract: prefix-scan;seed=123456789;batches=1000000;width=16;value-mask=65535
//
// prefix_scan — 1M batches of "fill 16 slots from the LCG, then run an
// in-place running sum over them". Two short sequential loops over the
// same small buffer: the fill is store-bound, the scan is a serial
// dependency chain of loads and adds.
//
// NURL has no fixed-size stack array: the 16-slot batch lives in a
// `malloc`ed `*u64` block, where the C and Rust peers use
// `uint64_t values[16]` / `[u64; 16]` on the stack.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else. `bench/bench.sh` gates
// on all five language implementations printing the same line before it
// reports a single timing number for the row.

@ main → i {
    : i width 16
    : u64 batches 1000000
    : *u64 values # *u64 ( malloc * width 8 )
    : ~ i z 0
    ~ < z width {
        = . values z # u64 0
        = z + z 1
    }

    : ~ u64 state 123456789
    : ~ u64 checksum 0
    : ~ u64 batch 0

    ~ < batch batches {
        : ~ i index 0
        ~ < index width {
            = state & + * state 1664525 1013904223 0xffffffff
            = . values index & state 0xffff
            = index + index 1
        }

        = index 1
        ~ < index width {
            = . values index + . values index . values - index 1
            = index + index 1
        }

        = checksum ^^ checksum . values 15
        = batch + batch 1
    }

    : u64 result ^^ state checksum
    ( free values )
    ( nurl_print_int # i & result 0x7fffffffffffffff )
    ^ 0
}
