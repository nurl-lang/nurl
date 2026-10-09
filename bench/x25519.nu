// benchmark-contract: x25519;rfc7748;k=u=9;iterations=1000;checksum=k-le64
//
// x25519 — RFC 7748 X25519 Diffie-Hellman through the standard library's
// variable-base `x25519` (stdlib/std/x25519.nu): the TweetNaCl Montgomery
// ladder over the curve25519-donna-c64 field (five limbs at radix 2^51,
// 64x64->128 products via `nurl_umulhi` / `nurl_mac_*`) and the ref10
// inversion chain. The C and Rust peers carry that same formulation
// written out by hand, with their native 128-bit integers — their
// standard libraries have no X25519. On a CPU with x86-64-v3 the ladder
// runs its `simd` clone, chosen at run time, whose products are BMI2
// `mulx`; the peers are built for baseline x86-64 like every row and
// multiply with `mul`, the instruction the library's baseline lowering
// uses everywhere else.
//
// The workload is RFC 7748 §5.2's iteration test: k = u = 9, then 1000
// times (k, u) <- (X25519(k, u), k), so each scalar multiplication
// consumes the previous result and the whole run is one serial chain. At
// x1 the final k is the RFC's own 1000-iteration value,
// 684cf59ba8330955…, so the printed line is 6127485567278337128.
//
// Contract: the process prints exactly one line — the final k's first
// eight bytes as a little-endian integer, masked to 63 bits — and nothing
// else. `bench/bench.sh` gates on the NURL, C and Rust implementations
// printing the same line before it reports a timing.
$ `stdlib/core/vec.nu`
$ `stdlib/std/x25519.nu`

// v[k], or 0 past the end (every index here is in range).
@ byte_at ( Vec u ) v i k → u64 {
    ?? ( vec_get [u] v k ) { T x → ^ # u64 x F _ → ^ # u64 0 }
}

@ main → i {
    // The workload multiplier: bench/bench.sh / wasmbench.sh --scale N rewrites this 1.
    : u64 BENCH_SCALE 1
    : i iterations * 1000 # i BENCH_SCALE
    : ~ ( Vec u ) k ( vec_zeroed [u] 32 )
    : ~ ( Vec u ) u ( vec_zeroed [u] 32 )
    ( vec_set [u] k 0 # u 9 )
    ( vec_set [u] u 0 # u 9 )

    : ~ i it 0
    ~ < it iterations {
        : ( Vec u ) r ( x25519 k u )
        = u k
        = k r
        = it + it 1
    }

    : ~ u64 v 0
    : ~ i i 7
    ~ >= i 0 {
        = v | << v 8 ( byte_at k i )
        = i - i 1
    }
    ( nurl_println_int # i & v 0x7fffffffffffffff )
    ^ 0
}
