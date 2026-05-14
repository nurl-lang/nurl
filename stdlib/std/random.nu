// stdlib/std/random.nu — secure random numbers
//
// Backed by `getrandom(2)` on Linux, `arc4random_buf` on macOS,
// `BCryptGenRandom` on Windows (runtime §17). Suitable for session
// tokens, request IDs, retry jitter, salts.
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
// value (for hex display, bit packing) just feed it through
// `nurl_str_int` or use `rand_hex_str 8` directly.

$ `stdlib/core/string.nu`
$ `stdlib/std/int.nu`

@ rand_u64 → i {
    ^ ( nurl_rand_u64 )
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
        = v & ( nurl_rand_u64 ) mask
        // rand_u64 may return negative (top bit set in signed i64); the
        // mask is positive, so & yields 0..mask. The value is rejected if
        // it's >= span.
        ? < v span { = done T } {}
    }
    ^ + from v
}

@ rand_hex_str i n → String {
    : s raw ( nurl_rand_bytes_hex n )
    : String out ( string_from raw )
    ( nurl_free raw )
    ^ out
}
