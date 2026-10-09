// stdlib/std/hash_sha1.nu — RFC 3174 SHA-1 in pure NURL.
//
// Algorithm strength: SHA-1 is collision-broken and MUST NOT be used
// for new security-sensitive authentication. Provided for protocols
// that mandate it — WebSocket handshake `Sec-WebSocket-Accept` per
// RFC 6455 §4.2.2, git object IDs, legacy APIs.
//
// API:
//   ( sha1_pure ( Vec u ) data ) → ( Vec u )   20-byte digest (owned)
//
// Shape: the five working words and the sixteen-word message schedule are
// scalar locals; each of the 80 steps is one `inline` call that takes the
// words it updates `inout`, written out with the working words already
// rotated into place, so no step moves a word and no round selects its
// function at run time. The schedule is the 16-word ring of FIPS 180-4
// §6.1.3, expanded in place one word ahead of the step that reads it.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// Left-rotate u32 by c bits (0 < c < 32).
inline @ __sha1_rotl u32 x i c → u32 {
    // One `rol` instruction via the compiler's funnel-shift primitive.
    ^ # u32 ( nurl_rotl32 # u64 x # u64 c )
}

// One step, e += rotl(a, 5) + f(b, c, d) + K + w; b = rotl(b, 30) — for
// each of the four 20-step groups (Ch, Parity, Maj, Parity).
inline @ __sha1_f1 u32 a inout u32 b u32 c u32 d inout u32 e u32 w → v {
    = e + + + + e ( __sha1_rotl a 5 ) | & b c & ~ b d # u32 1518500249 w  // 0x5A827999
    = b ( __sha1_rotl b 30 )
}

inline @ __sha1_f2 u32 a inout u32 b u32 c u32 d inout u32 e u32 w → v {
    = e + + + + e ( __sha1_rotl a 5 ) ^^ ^^ b c d # u32 1859775393 w  // 0x6ED9EBA1
    = b ( __sha1_rotl b 30 )
}

inline @ __sha1_f3 u32 a inout u32 b u32 c u32 d inout u32 e u32 w → v {
    = e + + + + e ( __sha1_rotl a 5 ) | & b c & d | b c # u32 2400959708 w  // 0x8F1BBCDC
    = b ( __sha1_rotl b 30 )
}

inline @ __sha1_f4 u32 a inout u32 b u32 c u32 d inout u32 e u32 w → v {
    = e + + + + e ( __sha1_rotl a 5 ) ^^ ^^ b c d # u32 3395469782 w  // 0xCA62C1D6
    = b ( __sha1_rotl b 30 )
}

// The big-endian u32 at `blk[off .. off+4]`; every caller reads inside a
// block it has already sized, so the out-of-range arm never runs.
@ __sha1_w ( Vec u ) blk i off → u32 {
    ?? ( bytes_read_u32_be blk off ) { T x → ^ x F → ^ # u32 0 }
}

// ── Transform: one 64-byte block at `blk[off ..]` into h0..h4. ─────
// The 80-word schedule is expanded into the caller's scratch `wp` first;
// the steps then run five to a pass, each one `inline` call updating the
// two words a step changes (`inout`) with the variables written already
// rotated into their roles, so five steps bring a..e back to their own
// names and no step moves a word. Fully unrolled over a schedule held in
// sixteen locals the transform was no faster, and a program hashing with
// SHA-1 compiled 60 % more instructions.
@ __sha1_transform inout u32 h0 inout u32 h1 inout u32 h2 inout u32 h3 inout u32 h4 ( Vec u ) blk i off * u32 wp → v {
    : ~ i k 0
    ~ < k 16 { = . wp k ( __sha1_w blk + off * k 4 ) = k + k 1 }
    ~ < k 80 {
        = . wp k ( __sha1_rotl ^^ ^^ ^^ . wp - k 3 . wp - k 8 . wp - k 14 . wp - k 16 1 )
        = k + k 1
    }

    : ~ u32 a h0
    : ~ u32 b h1
    : ~ u32 c h2
    : ~ u32 d h3
    : ~ u32 e h4

    : ~ i t 0
    ~ < t 20 {
        ( __sha1_f1 a b c d e . wp t )
        ( __sha1_f1 e a b c d . wp + t 1 )
        ( __sha1_f1 d e a b c . wp + t 2 )
        ( __sha1_f1 c d e a b . wp + t 3 )
        ( __sha1_f1 b c d e a . wp + t 4 )
        = t + t 5
    }
    = t 20
    ~ < t 40 {
        ( __sha1_f2 a b c d e . wp t )
        ( __sha1_f2 e a b c d . wp + t 1 )
        ( __sha1_f2 d e a b c . wp + t 2 )
        ( __sha1_f2 c d e a b . wp + t 3 )
        ( __sha1_f2 b c d e a . wp + t 4 )
        = t + t 5
    }
    = t 40
    ~ < t 60 {
        ( __sha1_f3 a b c d e . wp t )
        ( __sha1_f3 e a b c d . wp + t 1 )
        ( __sha1_f3 d e a b c . wp + t 2 )
        ( __sha1_f3 c d e a b . wp + t 3 )
        ( __sha1_f3 b c d e a . wp + t 4 )
        = t + t 5
    }
    = t 60
    ~ < t 80 {
        ( __sha1_f4 a b c d e . wp t )
        ( __sha1_f4 e a b c d . wp + t 1 )
        ( __sha1_f4 d e a b c . wp + t 2 )
        ( __sha1_f4 c d e a b . wp + t 3 )
        ( __sha1_f4 b c d e a . wp + t 4 )
        = t + t 5
    }

    = h0 + h0 a
    = h1 + h1 b
    = h2 + h2 c
    = h3 + h3 d
    = h4 + h4 e
}

// ── Public entry — same shape as `md5_pure`. ──────────────────────

@ sha1_pure ( Vec u ) data → ( Vec u ) {
    : ~ u32 h0 # u32 1732584193  // 0x67452301
    : ~ u32 h1 # u32 4023233417  // 0xEFCDAB89
    : ~ u32 h2 # u32 2562383102  // 0x98BADCFE
    : ~ u32 h3 # u32 271733878  // 0x10325476
    : ~ u32 h4 # u32 3285377520  // 0xC3D2E1F0

    : i n ( vec_len [u] data )
    // the 80-word message schedule, one per hash
    : ( Vec u32 ) ws ( vec_with_cap [u32] 80 )
    : b _wl ( vec_set_len [u32] ws 80 )
    : *u32 wp ( vec_data [u32] ws )

    : ~ i off 0
    ~ <= + off 64 n {
        ( __sha1_transform h0 h1 h2 h3 h4 data off wp )
        = off + off 64
    }

    // Tail: leftover bytes + 0x80 + zero pad + 64-bit BIG-endian length.
    : ( Vec u ) tail ( vec_with_cap [u] 128 )
    : ~ i ti off
    ~ < ti n {
        ( vec_push [u] tail ( vec_at [u] data ti ) )
        = ti + ti 1
    }
    ( vec_push [u] tail # u 128 )
    : i leftover - n off
    : i after_one + leftover 1
    : i need_zeros ? <= after_one 56 - 56 after_one - 120 after_one
    : ~ i zi 0
    ~ < zi need_zeros {
        ( vec_push [u] tail # u 0 )
        = zi + zi 1
    }
    : i bitlen * n 8
    // big-endian: high bytes first
    ( vec_push [u] tail # u & >> bitlen 56 255 )
    ( vec_push [u] tail # u & >> bitlen 48 255 )
    ( vec_push [u] tail # u & >> bitlen 40 255 )
    ( vec_push [u] tail # u & >> bitlen 32 255 )
    ( vec_push [u] tail # u & >> bitlen 24 255 )
    ( vec_push [u] tail # u & >> bitlen 16 255 )
    ( vec_push [u] tail # u & >> bitlen 8 255 )
    ( vec_push [u] tail # u & bitlen 255 )

    : i tail_len ( vec_len [u] tail )
    : ~ i toff 0
    ~ < toff tail_len {
        ( __sha1_transform h0 h1 h2 h3 h4 tail toff wp )
        = toff + toff 64
    }

    // Serialise h0..h4 as 20 big-endian bytes.
    : ( Vec u ) out ( vec_with_cap [u] 20 )
    ( bytes_push_u32_be out h0 )
    ( bytes_push_u32_be out h1 )
    ( bytes_push_u32_be out h2 )
    ( bytes_push_u32_be out h3 )
    ( bytes_push_u32_be out h4 )
    ^ out
}
