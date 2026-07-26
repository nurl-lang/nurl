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
// Peer protocol (matches prefix_scan.c / prefix_scan.rs): the process
// normally prints nothing and reports the checksum through its exit
// status (`checksum & 0x7f`). Passing `--verify` writes the 8
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
    ^ ( finish result )
}
