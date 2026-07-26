// benchmark-contract: affine-mix;seed=123456789;iterations=50000000;mask=0x03ffffffffffffff
//
// affine_mix — 50M rounds of two chained affine steps over a 58-bit
// state. Every step depends on the previous one, so the loop cannot be
// folded into a closed form; the shifts keep the mix in the integer ALU.
//
// Peer protocol (matches affine_mix.c / affine_mix.rs): the process
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
    : u64 iterations 50000000
    : u64 mask 0x03ffffffffffffff
    : ~ u64 state 123456789
    : ~ u64 k 0

    ~ < k iterations {
        = state & + << state 3 k mask
        = state & - << state 2 3 mask
        = k + k 1
    }

    ^ ( finish state )
}
