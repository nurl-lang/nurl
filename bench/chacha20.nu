// benchmark-contract: chacha20;rfc8439;key=00..1f;nonce=000000090000004a00000000;counter=1;buffer=16384;passes=1024;checksum=fnv1a64-words
//
// chacha20 — the RFC 8439 stream cipher through the standard library's
// `chacha20_xor` (stdlib/std/chacha20poly1305.nu). A 16 KiB buffer is
// encrypted 1024 times (16 MiB of keystream), the block counter running on
// across passes (pass p starts at 1 + p*256) so no two blocks repeat; each
// pass encrypts the previous pass's ciphertext.
//
// The stdlib's kernels are written over vector lanes: four blocks at a
// time, each 128-bit lane holding one state word of all four, and eight
// at a time over 256-bit lanes in the function's `simd` clone, which runs
// when the CPU has x86-64-v3 (AVX2) — chosen at run time, so the same
// binary runs the four-block kernel elsewhere. The C and Rust peers carry
// the portable scalar RFC formulation (their standard libraries have no
// ChaCha20), the one the stdlib keeps as its big-endian fallback. That
// difference is what this row measures.
//
// The key, nonce and counter are RFC 8439 §2.3.2's block-function test
// vector, so the first keystream block is the one the RFC prints.
//
// Contract: the process prints exactly one line — an FNV-style fold of the
// final buffer's 64-bit little-endian words, masked to 63 bits — and
// nothing else. `bench/bench.sh` gates on the NURL, C and Rust
// implementations printing the same line before it reports a timing.
$ `stdlib/core/vec.nu`
$ `stdlib/std/chacha20poly1305.nu`

// v[k], or 0 past the end (every index here is in range).
@ byte_at ( Vec u ) v i k → u64 {
    ?? ( vec_get [u] v k ) { T x → ^ # u64 x F _ → ^ # u64 0 }
}

// The 8 bytes at v[o..o+7] as a little-endian integer.
@ le64_at ( Vec u ) v i o → u64 {
    : ~ u64 r 0
    : ~ i k 7
    ~ >= k 0 {
        = r | << r 8 ( byte_at v + o k )
        = k - k 1
    }
    ^ r
}

@ main → i {
    // The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : i passes * 1024 # i BENCH_SCALE
    : i len 16384
    : ( Vec u ) key ( vec_with_cap [u] 32 )
    : ~ i i 0
    ~ < i 32 {
        ( vec_push [u] key # u i )
        = i + i 1
    }
    : ( Vec u ) nonce ( vec_zeroed [u] 12 )
    ( vec_set [u] nonce 3 # u 9 )
    ( vec_set [u] nonce 7 # u 74 )
    : ~ ( Vec u ) buf ( vec_with_cap [u] len )
    = i 0
    ~ < i len {
        ( vec_push [u] buf # u & i 255 )
        = i + i 1
    }

    : ~ i pass 0
    ~ < pass passes {
        = buf ( chacha20_xor key + 1 * pass / len 64 nonce buf )
        = pass + pass 1
    }

    : ~ u64 h 0xcbf29ce484222325
    = i 0
    ~ < i len {
        = h * ^^ h ( le64_at buf i ) 0x100000001b3
        = i + i 8
    }
    ( nurl_println_int # i & h 0x7fffffffffffffff )
    ^ 0
}
