// benchmark-contract: branch-lcg32;seed=123456789;iterations=50000000;threshold=2147483648
//
// packet_classifier — 50M iterations that pick one of two LCGs based on
// the current state. The branch is data-dependent and ~50/50, so this is
// the branch-misprediction shape of the set: same work per iteration as
// stream_lcg, but the predictor cannot learn the pattern.
//
// Peer protocol (matches packet_classifier.c / packet_classifier.rs):
// the process normally prints nothing and reports the checksum through
// its exit status (`checksum & 0x7f`). Passing `--verify` writes the 8
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
    : u64 iterations 50000000
    : u64 threshold 2147483648
    : ~ u64 state 123456789
    : ~ u64 k 0

    ~ < k iterations {
        ? < state threshold
        { = state & + * state 1664525 1013904223 0xffffffff }
        { = state & + * state 22695477 1 0xffffffff }
        = k + k 1
    }

    ^ ( finish state )
}
