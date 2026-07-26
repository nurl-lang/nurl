// benchmark-contract: ring-write;seed=123456789;iterations=50000000;words=64;value=state32x2
//
// ring_write — 50M LCG steps, each storing a 64-bit word into a 64-slot
// ring buffer. Same arithmetic as stream_lcg plus one dependent store
// per iteration, so the store pipeline and the address computation are
// what separate the languages.
//
// NURL has no fixed-size stack array: the ring lives in a `malloc`ed
// `*u64` block, where the C and Rust peers use `uint64_t buf[64]` /
// `[u64; 64]` on the stack.
//
// Peer protocol (matches ring_write.c / ring_write.rs): the process
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
    : i words 64
    : u64 iterations 50000000
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
    ^ ( finish result )
}
