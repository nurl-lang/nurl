// benchmark-contract: histogram;seed=123456789;iterations=20000000;bins=64;index=state&63
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
// Peer protocol (matches histogram_bins.c / histogram_bins.rs): the
// process normally prints nothing and reports the checksum through its
// exit status (`checksum & 0x7f`). Passing `--verify` writes the 8
// little-endian checksum bytes to stdout — the C peer spells that
// `-DBENCH_VERIFY`, the Rust peer `--cfg bench_verify`.
& `c` @ putchar i c → i

@ emit_checksum u64 value → v {
    : ~ u64 x value
    : ~ i k 0
    ~ < k 8 {
        ( putchar # i & x 255 )
        = x >> x 8
        = k + k 1
    }
}

@ verify_requested → b {
    : i argc ( nurl_argc )
    : ~ i k 1
    ~ < k argc {
        ? == ( strcmp ( nurl_argv k ) `--verify` ) 0 { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ finish u64 value → i {
    ? ( verify_requested ) { ( emit_checksum value ) } {}
    ^ # i & value 0x7f
}

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
    ^ ( finish checksum )
}
