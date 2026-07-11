// stdlib/std/random.nu — secure random numbers (pure-NURL FFI)
//
// The runtime ships a single syscall-shaped bridge —
// `nurl_rand_fill(buf, n)` — that picks the right OS entropy source
// per platform (getrandom / arc4random_buf / BCryptGenRandom +
// /dev/urandom fallback). Everything else (the i64 pack, the hex
// encoder, the cap-to-4096 wrapper) is pure NURL here.
//
//   ( rand_u64 )                → i        full-range 64-bit signed
//                                          (interpret as unsigned for
//                                           round-trips through hex/string)
//   ( rand_range from to )      → i        uniform integer in [from, to)
//                                          when from < to; otherwise from.
//                                          Rejection-sampled, so unbiased.
//   ( rand_hex_str n )          → String   2*n lowercase hex chars from
//                                          n random bytes (n clamped to
//                                          [0, 4096])
//
// Note: rand_u64 returns a signed i; when you need an "unsigned" 8-byte
// value (for hex display, bit packing) feed it through `rand_hex_str 8`
// directly.

$ `stdlib/core/string.nu`

// Single syscall-shaped runtime bridge. Returns 1 on success, 0 on a
// total entropy failure (which the degraded /dev/urandom-or-PRNG fallback
// makes impossible on every supported target). Platform-branched in C:
// getrandom(2) on Linux, arc4random_buf on macOS, BCryptGenRandom on
// Windows, /dev/urandom otherwise.
& `c` @ nurl_rand_fill *u buf i n → i

// 0..9 → '0' (48), 10..15 → 'a' (97).
@ __rand_hex_digit i n → i {
    ? < n 10 { ^ + 48 n } {}
    ^ + 87 n
}

@ rand_u64 → i {
    : s buf ( nurl_zalloc 8 )
    : i r ( nurl_rand_fill # *u buf 8 )
    // Fail closed: nurl_rand_fill returns 0 only when every OS entropy
    // source failed and the runtime degraded to a non-cryptographic LCG.
    // Proceeding would hand predictable bytes to whoever asked for random
    // ones — panic instead (same contract as the tls/rsa/x509 draws).
    ? == r 0 { ( nurl_panic `random: CSPRNG (nurl_rand_fill) failed` ) } {}
    : *u p # *u buf
    : ~ i v 0
    : ~ i k 0
    ~ < k 8 {
        : i b & 255 # i . p k
        = v | * v 256 b
        = k + k 1
    }
    ( nurl_free buf )
    ^ v
}

// Uniform integer in [from, to). Empty / inverted range → returns from.
// Uses rejection sampling on a power-of-two mask of the range size to
// stay unbiased. The mask grows by doubling until it covers the range.
@ rand_range i from i to → i {
    ? >= from to { ^ from } {}
    : i span - to from
    // Find the smallest mask >= span (power-of-two minus 1).
    : ~ i mask 1
    ~ < mask span { = mask + * mask 2 1 }
    : ~ i v 0
    : ~ b done F
    ~ ! done {
        = v & ( rand_u64 ) mask
        // rand_u64 may return negative (top bit set in signed i64); the
        // mask is positive, so & yields 0..mask. The value is rejected if
        // it's >= span.
        ? < v span { = done T } {}
    }
    ^ + from v
}

@ rand_hex_str i n → String {
    ? <= n 0 { ^ ( string_with_cap 0 ) } {}
    : i cap ? > n 4096 4096 n
    : s buf ( nurl_zalloc cap )
    : i r ( nurl_rand_fill # *u buf cap )
    ? == r 0 { ( nurl_panic `random: CSPRNG (nurl_rand_fill) failed` ) } {}
    : *u p # *u buf
    : String out ( string_with_cap * cap 2 )
    : ~ i k 0
    ~ < k cap {
        : i b & 255 # i . p k
        ( string_push_char out ( __rand_hex_digit / b 16 ) )
        ( string_push_char out ( __rand_hex_digit & b 15 ) )
        = k + k 1
    }
    ( nurl_free buf )
    ^ out
}
