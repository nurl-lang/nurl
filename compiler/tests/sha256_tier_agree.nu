// sha256_tier_agree.nu — SHA-256's two block functions, the SHA-NI
// kernel (`__sha256_blocks_ni`, the SHA tier: docs/spec.md §4.1b) and
// the portable rounds, held to the same golden. On a CPU with the SHA
// extensions this runs the kernel; crypto_tier_ir.sh runs it again with
// NURL_CPU_SHA=0, and on a CPU without them it runs the portable path —
// one output for all three.
//
// The chain covers every message length from 0 to 1100 bytes, so every
// padding shape (one final block or two) and every run of 1 to 17 full
// blocks the kernel takes in one call; each digest is folded into the
// next message, so one wrong word anywhere changes the last line.
// FIPS 180-4's long vector (a million 'a') runs the kernel over 15 625
// blocks in a single run.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`

@ show s label ( Vec u ) d → v {
    : String hx ( bytes_to_hex d )
    ( nurl_print label ) ( nurl_print ( string_data hx ) ) ( nurl_print `\n` )
    ( string_free hx )
}

@ main → i {
    // acc = H(acc ‖ H(pattern(len))) for len = 0 … 1100, where
    // pattern(len)[k] = (k·131 + 7) & 255.
    : ~ ( Vec u ) acc ( vec_zeroed [u] 32 )
    : ~ i len 0
    ~ <= len 1100 {
        : ( Vec u ) m ( vec_with_cap [u] len )
        : ~ i k 0
        ~ < k len {
            ( vec_push [u] m # u & + * k 131 7 255 )
            = k + k 1
        }
        : ( Vec u ) both ( vec_with_cap [u] 64 )
        ( bytes_extend_bytes both acc )
        ( bytes_extend_bytes both ( sha256_pure m ) )
        = acc ( sha256_pure both )
        = len + len 1
    }
    ( show `chain 0..1100: ` acc )
    : ( Vec u ) mil ( vec_with_cap [u] 1000000 )
    : ~ i j 0
    ~ < j 1000000 {
        ( vec_push [u] mil # u 97 )
        = j + j 1
    }
    ( show `million a:     ` ( sha256_pure mil ) )
    ^ 0
}
