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

// Schedule: w[t] = rotl(w[t-16] ⊕ w[t-3] ⊕ w[t-8] ⊕ w[t-14], 1), with w[t-16]
// the ring slot w[t] overwrites.
inline @ __sha1_x inout u32 w u32 x u32 y u32 z → v {
    = w ( __sha1_rotl ^^ ^^ ^^ w x y z 1 )
}

// The big-endian u32 at `blk[off .. off+4]`; every caller reads inside a
// block it has already sized, so the out-of-range arm never runs.
@ __sha1_w ( Vec u ) blk i off → u32 {
    ?? ( bytes_read_u32_be blk off ) { T x → ^ x F → ^ # u32 0 }
}

// ── Transform: one 64-byte block at `blk[off ..]` into h0..h4. ─────

@ __sha1_transform inout u32 h0 inout u32 h1 inout u32 h2 inout u32 h3 inout u32 h4 ( Vec u ) blk i off → v {
    : ~ u32 w0 ( __sha1_w blk off )
    : ~ u32 w1 ( __sha1_w blk + off 4 )
    : ~ u32 w2 ( __sha1_w blk + off 8 )
    : ~ u32 w3 ( __sha1_w blk + off 12 )
    : ~ u32 w4 ( __sha1_w blk + off 16 )
    : ~ u32 w5 ( __sha1_w blk + off 20 )
    : ~ u32 w6 ( __sha1_w blk + off 24 )
    : ~ u32 w7 ( __sha1_w blk + off 28 )
    : ~ u32 w8 ( __sha1_w blk + off 32 )
    : ~ u32 w9 ( __sha1_w blk + off 36 )
    : ~ u32 w10 ( __sha1_w blk + off 40 )
    : ~ u32 w11 ( __sha1_w blk + off 44 )
    : ~ u32 w12 ( __sha1_w blk + off 48 )
    : ~ u32 w13 ( __sha1_w blk + off 52 )
    : ~ u32 w14 ( __sha1_w blk + off 56 )
    : ~ u32 w15 ( __sha1_w blk + off 60 )

    : ~ u32 a h0
    : ~ u32 b h1
    : ~ u32 c h2
    : ~ u32 d h3
    : ~ u32 e h4

    ( __sha1_f1 a b c d e w0 )
    ( __sha1_f1 e a b c d w1 )
    ( __sha1_f1 d e a b c w2 )
    ( __sha1_f1 c d e a b w3 )
    ( __sha1_f1 b c d e a w4 )
    ( __sha1_f1 a b c d e w5 )
    ( __sha1_f1 e a b c d w6 )
    ( __sha1_f1 d e a b c w7 )
    ( __sha1_f1 c d e a b w8 )
    ( __sha1_f1 b c d e a w9 )
    ( __sha1_f1 a b c d e w10 )
    ( __sha1_f1 e a b c d w11 )
    ( __sha1_f1 d e a b c w12 )
    ( __sha1_f1 c d e a b w13 )
    ( __sha1_f1 b c d e a w14 )
    ( __sha1_f1 a b c d e w15 )
    ( __sha1_x w0 w13 w8 w2 )
    ( __sha1_f1 e a b c d w0 )
    ( __sha1_x w1 w14 w9 w3 )
    ( __sha1_f1 d e a b c w1 )
    ( __sha1_x w2 w15 w10 w4 )
    ( __sha1_f1 c d e a b w2 )
    ( __sha1_x w3 w0 w11 w5 )
    ( __sha1_f1 b c d e a w3 )
    ( __sha1_x w4 w1 w12 w6 )
    ( __sha1_f2 a b c d e w4 )
    ( __sha1_x w5 w2 w13 w7 )
    ( __sha1_f2 e a b c d w5 )
    ( __sha1_x w6 w3 w14 w8 )
    ( __sha1_f2 d e a b c w6 )
    ( __sha1_x w7 w4 w15 w9 )
    ( __sha1_f2 c d e a b w7 )
    ( __sha1_x w8 w5 w0 w10 )
    ( __sha1_f2 b c d e a w8 )
    ( __sha1_x w9 w6 w1 w11 )
    ( __sha1_f2 a b c d e w9 )
    ( __sha1_x w10 w7 w2 w12 )
    ( __sha1_f2 e a b c d w10 )
    ( __sha1_x w11 w8 w3 w13 )
    ( __sha1_f2 d e a b c w11 )
    ( __sha1_x w12 w9 w4 w14 )
    ( __sha1_f2 c d e a b w12 )
    ( __sha1_x w13 w10 w5 w15 )
    ( __sha1_f2 b c d e a w13 )
    ( __sha1_x w14 w11 w6 w0 )
    ( __sha1_f2 a b c d e w14 )
    ( __sha1_x w15 w12 w7 w1 )
    ( __sha1_f2 e a b c d w15 )
    ( __sha1_x w0 w13 w8 w2 )
    ( __sha1_f2 d e a b c w0 )
    ( __sha1_x w1 w14 w9 w3 )
    ( __sha1_f2 c d e a b w1 )
    ( __sha1_x w2 w15 w10 w4 )
    ( __sha1_f2 b c d e a w2 )
    ( __sha1_x w3 w0 w11 w5 )
    ( __sha1_f2 a b c d e w3 )
    ( __sha1_x w4 w1 w12 w6 )
    ( __sha1_f2 e a b c d w4 )
    ( __sha1_x w5 w2 w13 w7 )
    ( __sha1_f2 d e a b c w5 )
    ( __sha1_x w6 w3 w14 w8 )
    ( __sha1_f2 c d e a b w6 )
    ( __sha1_x w7 w4 w15 w9 )
    ( __sha1_f2 b c d e a w7 )
    ( __sha1_x w8 w5 w0 w10 )
    ( __sha1_f3 a b c d e w8 )
    ( __sha1_x w9 w6 w1 w11 )
    ( __sha1_f3 e a b c d w9 )
    ( __sha1_x w10 w7 w2 w12 )
    ( __sha1_f3 d e a b c w10 )
    ( __sha1_x w11 w8 w3 w13 )
    ( __sha1_f3 c d e a b w11 )
    ( __sha1_x w12 w9 w4 w14 )
    ( __sha1_f3 b c d e a w12 )
    ( __sha1_x w13 w10 w5 w15 )
    ( __sha1_f3 a b c d e w13 )
    ( __sha1_x w14 w11 w6 w0 )
    ( __sha1_f3 e a b c d w14 )
    ( __sha1_x w15 w12 w7 w1 )
    ( __sha1_f3 d e a b c w15 )
    ( __sha1_x w0 w13 w8 w2 )
    ( __sha1_f3 c d e a b w0 )
    ( __sha1_x w1 w14 w9 w3 )
    ( __sha1_f3 b c d e a w1 )
    ( __sha1_x w2 w15 w10 w4 )
    ( __sha1_f3 a b c d e w2 )
    ( __sha1_x w3 w0 w11 w5 )
    ( __sha1_f3 e a b c d w3 )
    ( __sha1_x w4 w1 w12 w6 )
    ( __sha1_f3 d e a b c w4 )
    ( __sha1_x w5 w2 w13 w7 )
    ( __sha1_f3 c d e a b w5 )
    ( __sha1_x w6 w3 w14 w8 )
    ( __sha1_f3 b c d e a w6 )
    ( __sha1_x w7 w4 w15 w9 )
    ( __sha1_f3 a b c d e w7 )
    ( __sha1_x w8 w5 w0 w10 )
    ( __sha1_f3 e a b c d w8 )
    ( __sha1_x w9 w6 w1 w11 )
    ( __sha1_f3 d e a b c w9 )
    ( __sha1_x w10 w7 w2 w12 )
    ( __sha1_f3 c d e a b w10 )
    ( __sha1_x w11 w8 w3 w13 )
    ( __sha1_f3 b c d e a w11 )
    ( __sha1_x w12 w9 w4 w14 )
    ( __sha1_f4 a b c d e w12 )
    ( __sha1_x w13 w10 w5 w15 )
    ( __sha1_f4 e a b c d w13 )
    ( __sha1_x w14 w11 w6 w0 )
    ( __sha1_f4 d e a b c w14 )
    ( __sha1_x w15 w12 w7 w1 )
    ( __sha1_f4 c d e a b w15 )
    ( __sha1_x w0 w13 w8 w2 )
    ( __sha1_f4 b c d e a w0 )
    ( __sha1_x w1 w14 w9 w3 )
    ( __sha1_f4 a b c d e w1 )
    ( __sha1_x w2 w15 w10 w4 )
    ( __sha1_f4 e a b c d w2 )
    ( __sha1_x w3 w0 w11 w5 )
    ( __sha1_f4 d e a b c w3 )
    ( __sha1_x w4 w1 w12 w6 )
    ( __sha1_f4 c d e a b w4 )
    ( __sha1_x w5 w2 w13 w7 )
    ( __sha1_f4 b c d e a w5 )
    ( __sha1_x w6 w3 w14 w8 )
    ( __sha1_f4 a b c d e w6 )
    ( __sha1_x w7 w4 w15 w9 )
    ( __sha1_f4 e a b c d w7 )
    ( __sha1_x w8 w5 w0 w10 )
    ( __sha1_f4 d e a b c w8 )
    ( __sha1_x w9 w6 w1 w11 )
    ( __sha1_f4 c d e a b w9 )
    ( __sha1_x w10 w7 w2 w12 )
    ( __sha1_f4 b c d e a w10 )
    ( __sha1_x w11 w8 w3 w13 )
    ( __sha1_f4 a b c d e w11 )
    ( __sha1_x w12 w9 w4 w14 )
    ( __sha1_f4 e a b c d w12 )
    ( __sha1_x w13 w10 w5 w15 )
    ( __sha1_f4 d e a b c w13 )
    ( __sha1_x w14 w11 w6 w0 )
    ( __sha1_f4 c d e a b w14 )
    ( __sha1_x w15 w12 w7 w1 )
    ( __sha1_f4 b c d e a w15 )

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

    : ~ i off 0
    ~ <= + off 64 n {
        ( __sha1_transform h0 h1 h2 h3 h4 data off )
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
        ( __sha1_transform h0 h1 h2 h3 h4 tail toff )
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
