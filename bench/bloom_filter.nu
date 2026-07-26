// benchmark-contract: bloom-filter;seed=123456789;build=10000;queries=4000000;words=256;lanes=4
//
// bloom_filter — build a 256-word split-block Bloom filter from 10k
// 64-bit hashes, then run 4M membership queries against it. Each
// operation touches 4 lanes, and every lane's word index and bit index
// come from a different slice of the hash: 4 unpredictable loads per
// query over a 2 KB working set that fits in L1.
//
// NURL has no fixed-size stack array: the filter and the LCG state live
// in `malloc`ed blocks, where the C and Rust peers use
// `uint64_t filter[256]` / `[u64; 256]` on the stack. `lcg_step` takes
// the state by pointer, mirroring the peers' `uint64_t*` / `&mut u64`.
//
// Contract: the process prints exactly one line — the checksum in
// decimal, masked to 63 bits — and nothing else. `bench/bench.sh` gates
// on all five language implementations printing the same line before it
// reports a single timing number for the row.

// One step of the 32-bit LCG, state held by pointer so a single stream
// feeds both halves of every 64-bit hash.
@ lcg_step * u64 st → u64 {
    : ~ u64 s . st 0
    = s & + * s 1664525 1013904223 0xffffffff
    = . st 0 s
    ^ s
}

@ split_block_insert * u64 filter u64 hash → v {
    : ~ i lane 0
    ~ < lane 4 {
        : u64 word & >> hash * lane 8 255
        : u64 bit & >> hash + * lane 11 3 63
        = . filter word | . filter word << # u64 1 bit
        = lane + lane 1
    }
}

// Returns 1 when all four lanes are set, else 0 — the peers' `hit`
// accumulator, kept as an integer so the caller can add it directly.
@ split_block_maybe_contains * u64 filter u64 hash → u64 {
    : ~ u64 hit 1
    : ~ i lane 0
    ~ < lane 4 {
        : u64 word & >> hash * lane 8 255
        : u64 bit & >> hash + * lane 11 3 63
        = hit & hit & >> . filter word bit 1
        = lane + lane 1
    }
    ^ hit
}

@ main → i {
    : *u64 st # *u64 ( malloc 8 )
    = . st 0 # u64 123456789
    : *u64 filter # *u64 ( malloc * 256 8 )
    : ~ i z 0
    ~ < z 256 {
        = . filter z # u64 0
        = z + z 1
    }

    : ~ i k 0
    ~ < k 10000 {
        : u64 high ( lcg_step st )
        : u64 low ( lcg_step st )
        ( split_block_insert filter | << high 32 low )
        = k + k 1
    }

    : ~ u64 hits 0
    = k 0
    ~ < k 4000000 {
        : u64 high ( lcg_step st )
        : u64 low ( lcg_step st )
        = hits + hits ( split_block_maybe_contains filter | << high 32 low )
        = k + k 1
    }

    ( free filter )
    ( free st )
    ( nurl_print_int # i & hits 0x7fffffffffffffff )
    ^ 0
}
