// stdlib/std/hash_md5.nu — RFC 1321 MD5 in pure NURL.
//
// Algorithm strength: MD5 is collision-broken and MUST NOT be used to
// authenticate data or hash secrets. Provided for compatibility with
// protocols and formats that mandate it (RFC 1321 itself, S3 ETags,
// git object IDs in some legacy paths, file checksums).
//
// API:
//   ( md5_pure ( Vec u ) data ) → ( Vec u )   16-byte digest (owned)
//
// `stdlib/std/hash.nu`'s `md5_bytes` calls this directly; the public
// surface is unchanged.
//
// Shape: the four working words and the sixteen message words are scalar
// locals, and each of the 64 steps is one `inline` call that updates its
// word `inout` — written out with the words already rotated into place,
// and with the step's message index, sine constant T_i (RFC 1321 §3.4) and
// rotation as literals, so nothing is looked up at run time.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// Left-rotate u32 by c bits (0 < c < 32).
inline @ __md5_rotl u32 x i c → u32 {
    // One `rol` instruction via the compiler's funnel-shift primitive.
    ^ # u32 ( nurl_rotl32 # u64 x # u64 c )
}

// One step, a = b + rotl(a + f(b, c, d) + x + t, s) — for each of the four
// rounds' functions F, G, H, I.
inline @ __md5_ff inout u32 a u32 b u32 c u32 d u32 x u32 t i s → v {
    = a + b ( __md5_rotl + + + a | & b c & ~ b d x t s )
}

inline @ __md5_gg inout u32 a u32 b u32 c u32 d u32 x u32 t i s → v {
    = a + b ( __md5_rotl + + + a | & d b & ~ d c x t s )
}

inline @ __md5_hh inout u32 a u32 b u32 c u32 d u32 x u32 t i s → v {
    = a + b ( __md5_rotl + + + a ^^ ^^ b c d x t s )
}

inline @ __md5_ii inout u32 a u32 b u32 c u32 d u32 x u32 t i s → v {
    = a + b ( __md5_rotl + + + a ^^ c | b ~ d x t s )
}

// The little-endian u32 at `blk[off .. off+4]`; every caller reads inside
// a block it has already sized, so the out-of-range arm never runs.
@ __md5_w ( Vec u ) blk i off → u32 {
    ?? ( bytes_read_u32_le blk off ) { T x → ^ x F → ^ # u32 0 }
}

// ── Transform: one 64-byte block at `blk[off ..]` into h0..h3. ─────

@ __md5_transform inout u32 h0 inout u32 h1 inout u32 h2 inout u32 h3 ( Vec u ) blk i off → v {
    : u32 m0 ( __md5_w blk off )
    : u32 m1 ( __md5_w blk + off 4 )
    : u32 m2 ( __md5_w blk + off 8 )
    : u32 m3 ( __md5_w blk + off 12 )
    : u32 m4 ( __md5_w blk + off 16 )
    : u32 m5 ( __md5_w blk + off 20 )
    : u32 m6 ( __md5_w blk + off 24 )
    : u32 m7 ( __md5_w blk + off 28 )
    : u32 m8 ( __md5_w blk + off 32 )
    : u32 m9 ( __md5_w blk + off 36 )
    : u32 m10 ( __md5_w blk + off 40 )
    : u32 m11 ( __md5_w blk + off 44 )
    : u32 m12 ( __md5_w blk + off 48 )
    : u32 m13 ( __md5_w blk + off 52 )
    : u32 m14 ( __md5_w blk + off 56 )
    : u32 m15 ( __md5_w blk + off 60 )

    : ~ u32 a h0
    : ~ u32 b h1
    : ~ u32 c h2
    : ~ u32 d h3

    ( __md5_ff a b c d m0 # u32 3614090360 7 )
    ( __md5_ff d a b c m1 # u32 3905402710 12 )
    ( __md5_ff c d a b m2 # u32 606105819 17 )
    ( __md5_ff b c d a m3 # u32 3250441966 22 )
    ( __md5_ff a b c d m4 # u32 4118548399 7 )
    ( __md5_ff d a b c m5 # u32 1200080426 12 )
    ( __md5_ff c d a b m6 # u32 2821735955 17 )
    ( __md5_ff b c d a m7 # u32 4249261313 22 )
    ( __md5_ff a b c d m8 # u32 1770035416 7 )
    ( __md5_ff d a b c m9 # u32 2336552879 12 )
    ( __md5_ff c d a b m10 # u32 4294925233 17 )
    ( __md5_ff b c d a m11 # u32 2304563134 22 )
    ( __md5_ff a b c d m12 # u32 1804603682 7 )
    ( __md5_ff d a b c m13 # u32 4254626195 12 )
    ( __md5_ff c d a b m14 # u32 2792965006 17 )
    ( __md5_ff b c d a m15 # u32 1236535329 22 )
    ( __md5_gg a b c d m1 # u32 4129170786 5 )
    ( __md5_gg d a b c m6 # u32 3225465664 9 )
    ( __md5_gg c d a b m11 # u32 643717713 14 )
    ( __md5_gg b c d a m0 # u32 3921069994 20 )
    ( __md5_gg a b c d m5 # u32 3593408605 5 )
    ( __md5_gg d a b c m10 # u32 38016083 9 )
    ( __md5_gg c d a b m15 # u32 3634488961 14 )
    ( __md5_gg b c d a m4 # u32 3889429448 20 )
    ( __md5_gg a b c d m9 # u32 568446438 5 )
    ( __md5_gg d a b c m14 # u32 3275163606 9 )
    ( __md5_gg c d a b m3 # u32 4107603335 14 )
    ( __md5_gg b c d a m8 # u32 1163531501 20 )
    ( __md5_gg a b c d m13 # u32 2850285829 5 )
    ( __md5_gg d a b c m2 # u32 4243563512 9 )
    ( __md5_gg c d a b m7 # u32 1735328473 14 )
    ( __md5_gg b c d a m12 # u32 2368359562 20 )
    ( __md5_hh a b c d m5 # u32 4294588738 4 )
    ( __md5_hh d a b c m8 # u32 2272392833 11 )
    ( __md5_hh c d a b m11 # u32 1839030562 16 )
    ( __md5_hh b c d a m14 # u32 4259657740 23 )
    ( __md5_hh a b c d m1 # u32 2763975236 4 )
    ( __md5_hh d a b c m4 # u32 1272893353 11 )
    ( __md5_hh c d a b m7 # u32 4139469664 16 )
    ( __md5_hh b c d a m10 # u32 3200236656 23 )
    ( __md5_hh a b c d m13 # u32 681279174 4 )
    ( __md5_hh d a b c m0 # u32 3936430074 11 )
    ( __md5_hh c d a b m3 # u32 3572445317 16 )
    ( __md5_hh b c d a m6 # u32 76029189 23 )
    ( __md5_hh a b c d m9 # u32 3654602809 4 )
    ( __md5_hh d a b c m12 # u32 3873151461 11 )
    ( __md5_hh c d a b m15 # u32 530742520 16 )
    ( __md5_hh b c d a m2 # u32 3299628645 23 )
    ( __md5_ii a b c d m0 # u32 4096336452 6 )
    ( __md5_ii d a b c m7 # u32 1126891415 10 )
    ( __md5_ii c d a b m14 # u32 2878612391 15 )
    ( __md5_ii b c d a m5 # u32 4237533241 21 )
    ( __md5_ii a b c d m12 # u32 1700485571 6 )
    ( __md5_ii d a b c m3 # u32 2399980690 10 )
    ( __md5_ii c d a b m10 # u32 4293915773 15 )
    ( __md5_ii b c d a m1 # u32 2240044497 21 )
    ( __md5_ii a b c d m8 # u32 1873313359 6 )
    ( __md5_ii d a b c m15 # u32 4264355552 10 )
    ( __md5_ii c d a b m6 # u32 2734768916 15 )
    ( __md5_ii b c d a m13 # u32 1309151649 21 )
    ( __md5_ii a b c d m4 # u32 4149444226 6 )
    ( __md5_ii d a b c m11 # u32 3174756917 10 )
    ( __md5_ii c d a b m2 # u32 718787259 15 )
    ( __md5_ii b c d a m9 # u32 3951481745 21 )

    = h0 + h0 a
    = h1 + h1 b
    = h2 + h2 c
    = h3 + h3 d
}

// ── Public entry — same shape as runtime-backed `md5_bytes`. ───────

@ md5_pure ( Vec u ) data → ( Vec u ) {
    // State: A, B, C, D per RFC 1321 §3.3.
    : ~ u32 h0 # u32 1732584193  // 0x67452301
    : ~ u32 h1 # u32 4023233417  // 0xefcdab89
    : ~ u32 h2 # u32 2562383102  // 0x98badcfe
    : ~ u32 h3 # u32 271733878  // 0x10325476

    : i n ( vec_len [u] data )

    // Process complete 64-byte blocks straight from the input.
    : ~ i off 0
    ~ <= + off 64 n {
        ( __md5_transform h0 h1 h2 h3 data off )
        = off + off 64
    }

    // Build the tail block: leftover bytes + 0x80 + zero padding +
    // 64-bit little-endian bit-length, transformed as 1 or 2 blocks.
    : ( Vec u ) tail ( vec_with_cap [u] 128 )
    : ~ i ti off
    ~ < ti n {
        ( vec_push [u] tail ( vec_at [u] data ti ) )
        = ti + ti 1
    }
    // Append the mandatory 0x80 byte.
    ( vec_push [u] tail # u 128 )
    // Pad with zeros until length ≡ 56 (mod 64).
    : i leftover - n off
    : i after_one + leftover 1
    : i need_zeros ? <= after_one 56 - 56 after_one - 120 after_one
    : ~ i zi 0
    ~ < zi need_zeros {
        ( vec_push [u] tail # u 0 )
        = zi + zi 1
    }
    // Append 64-bit bit-length little-endian.
    : i bitlen * n 8
    ( vec_push [u] tail # u & bitlen 255 )
    ( vec_push [u] tail # u & >> bitlen 8 255 )
    ( vec_push [u] tail # u & >> bitlen 16 255 )
    ( vec_push [u] tail # u & >> bitlen 24 255 )
    ( vec_push [u] tail # u & >> bitlen 32 255 )
    ( vec_push [u] tail # u & >> bitlen 40 255 )
    ( vec_push [u] tail # u & >> bitlen 48 255 )
    ( vec_push [u] tail # u & >> bitlen 56 255 )

    // Transform 1 or 2 blocks of tail.
    : i tail_len ( vec_len [u] tail )
    : ~ i toff 0
    ~ < toff tail_len {
        ( __md5_transform h0 h1 h2 h3 tail toff )
        = toff + toff 64
    }

    // Serialise h0..h3 as 16 little-endian bytes.
    : ( Vec u ) out ( vec_with_cap [u] 16 )
    ( bytes_push_u32_le out h0 )
    ( bytes_push_u32_le out h1 )
    ( bytes_push_u32_le out h2 )
    ( bytes_push_u32_le out h3 )
    ^ out
}
