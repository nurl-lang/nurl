// stdlib/std/hash_blake2b.nu — BLAKE2b-512 in pure NURL (RFC 7693).
//
// Unkeyed BLAKE2b with a 64-byte digest — the hash minisign uses to prehash a
// message before the Ed25519 signature (algorithm `ED`). See stdlib/std/minisign.nu.
//
// API:
//   ( blake2b512_pure ( Vec u ) data ) → ( Vec u )   64-byte digest
//
// 64-bit words, 128-byte blocks, 12 rounds. u64 constants above 2^63-1 are
// written as their negative-two's-complement i64 (no hex literals); `# u64 -N`
// reinterprets the bit pattern.
//
// Shape: the sixteen working words, the sixteen message words and the eight
// chaining words are scalar locals, never a Vec. The mixing function G and
// the round take their working words `inout`, and both are `inline`, so after
// inlining every word is an SSA value the register allocator sees whole — the
// same code the C reference gets from its G/ROUND macros. The message
// schedule σ is not a table: each of the twelve round calls below passes the
// message words in that round's σ order, so every gather is resolved at
// compile time and costs nothing at run time. No bounds check survives in the
// rounds, because there is nothing indexed left in them.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// G, the quarter-round, on four working words in place.
inline @ __b2b_g inout u64 a inout u64 b inout u64 c inout u64 d u64 x u64 y → v {
    = a + + a b x
    = d ( nurl_rotr64 ^^ d a 32 )
    = c + c d
    = b ( nurl_rotr64 ^^ b c 24 )
    = a + + a b y
    = d ( nurl_rotr64 ^^ d a 16 )
    = c + c d
    = b ( nurl_rotr64 ^^ b c 63 )
}

// One round: the four column mixes, then the four diagonal mixes. s0..s15 are
// the message words already permuted by this round's σ row.
inline @ __b2b_round inout u64 v0 inout u64 v1 inout u64 v2 inout u64 v3 inout u64 v4 inout u64 v5 inout u64 v6 inout u64 v7 inout u64 v8 inout u64 v9 inout u64 v10 inout u64 v11 inout u64 v12 inout u64 v13 inout u64 v14 inout u64 v15 u64 s0 u64 s1 u64 s2 u64 s3 u64 s4 u64 s5 u64 s6 u64 s7 u64 s8 u64 s9 u64 s10 u64 s11 u64 s12 u64 s13 u64 s14 u64 s15 → v {
    ( __b2b_g v0 v4 v8 v12 s0 s1 )
    ( __b2b_g v1 v5 v9 v13 s2 s3 )
    ( __b2b_g v2 v6 v10 v14 s4 s5 )
    ( __b2b_g v3 v7 v11 v15 s6 s7 )
    ( __b2b_g v0 v5 v10 v15 s8 s9 )
    ( __b2b_g v1 v6 v11 v12 s10 s11 )
    ( __b2b_g v2 v7 v8 v13 s12 s13 )
    ( __b2b_g v3 v4 v9 v14 s14 s15 )
}

// The little-endian u64 at `blk[off .. off+8]`. Every caller reads inside a
// block it has already sized, so the out-of-range arm never runs.
@ __b2b_m ( Vec u ) blk i off → u64 {
    ?? ( bytes_read_u64_le blk off ) { T x → ^ x F → ^ # u64 0 }
}

// Compress the 128-byte block at `blk[off ..]` into the chaining words h0..h7.
// `t` = bytes hashed through this block (the high counter word is always 0
// for a Vec-sized input); `last` marks the final block.
@ __b2b_compress inout u64 h0 inout u64 h1 inout u64 h2 inout u64 h3 inout u64 h4 inout u64 h5 inout u64 h6 inout u64 h7 ( Vec u ) blk i off u64 t b last → v {
    : u64 m0 ( __b2b_m blk off )
    : u64 m1 ( __b2b_m blk + off 8 )
    : u64 m2 ( __b2b_m blk + off 16 )
    : u64 m3 ( __b2b_m blk + off 24 )
    : u64 m4 ( __b2b_m blk + off 32 )
    : u64 m5 ( __b2b_m blk + off 40 )
    : u64 m6 ( __b2b_m blk + off 48 )
    : u64 m7 ( __b2b_m blk + off 56 )
    : u64 m8 ( __b2b_m blk + off 64 )
    : u64 m9 ( __b2b_m blk + off 72 )
    : u64 m10 ( __b2b_m blk + off 80 )
    : u64 m11 ( __b2b_m blk + off 88 )
    : u64 m12 ( __b2b_m blk + off 96 )
    : u64 m13 ( __b2b_m blk + off 104 )
    : u64 m14 ( __b2b_m blk + off 112 )
    : u64 m15 ( __b2b_m blk + off 120 )

    // v = h ‖ IV, with the counter folded into v12 and the final-block flag
    // into v14 (the IV words are those of SHA-512).
    : ~ u64 v0 h0
    : ~ u64 v1 h1
    : ~ u64 v2 h2
    : ~ u64 v3 h3
    : ~ u64 v4 h4
    : ~ u64 v5 h5
    : ~ u64 v6 h6
    : ~ u64 v7 h7
    : ~ u64 v8 # u64 7640891576956012808
    : ~ u64 v9 # u64 -4942790177534073029
    : ~ u64 v10 # u64 4354685564936845355
    : ~ u64 v11 # u64 -6534734903238641935
    : ~ u64 v12 ^^ # u64 5840696475078001361 t
    : ~ u64 v13 # u64 -7276294671716946913
    : ~ u64 v14 # u64 2270897969802886507
    : ~ u64 v15 # u64 6620516959819538809
    ? last { = v14 ~ v14 } {}

    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m14 m10 m4 m8 m9 m15 m13 m6 m1 m12 m0 m2 m11 m7 m5 m3 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m11 m8 m12 m0 m5 m2 m15 m13 m10 m14 m3 m6 m7 m1 m9 m4 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m7 m9 m3 m1 m13 m12 m11 m14 m2 m6 m5 m10 m4 m0 m15 m8 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m9 m0 m5 m7 m2 m4 m10 m15 m14 m1 m11 m12 m6 m8 m3 m13 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m2 m12 m6 m10 m0 m11 m8 m3 m4 m13 m7 m5 m15 m14 m1 m9 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m12 m5 m1 m15 m14 m13 m4 m10 m0 m7 m6 m3 m9 m2 m8 m11 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m13 m11 m7 m14 m12 m1 m3 m9 m5 m0 m15 m4 m8 m6 m2 m10 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m6 m15 m14 m9 m11 m3 m0 m8 m12 m2 m13 m7 m1 m4 m10 m5 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m10 m2 m8 m4 m7 m6 m1 m5 m15 m11 m9 m14 m3 m12 m13 m0 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 )
    ( __b2b_round v0 v1 v2 v3 v4 v5 v6 v7 v8 v9 v10 v11 v12 v13 v14 v15 m14 m10 m4 m8 m9 m15 m13 m6 m1 m12 m0 m2 m11 m7 m5 m3 )

    = h0 ^^ ^^ h0 v0 v8
    = h1 ^^ ^^ h1 v1 v9
    = h2 ^^ ^^ h2 v2 v10
    = h3 ^^ ^^ h3 v3 v11
    = h4 ^^ ^^ h4 v4 v12
    = h5 ^^ ^^ h5 v5 v13
    = h6 ^^ ^^ h6 v6 v14
    = h7 ^^ ^^ h7 v7 v15
}

@ blake2b512_pure ( Vec u ) data → ( Vec u ) {
    // h = IV, with h0 ^= 0x01010040 (digest length 64, no key, fanout and
    // depth 1).
    : ~ u64 h0 ^^ # u64 7640891576956012808 # u64 16842816
    : ~ u64 h1 # u64 -4942790177534073029
    : ~ u64 h2 # u64 4354685564936845355
    : ~ u64 h3 # u64 -6534734903238641935
    : ~ u64 h4 # u64 5840696475078001361
    : ~ u64 h5 # u64 -7276294671716946913
    : ~ u64 h6 # u64 2270897969802886507
    : ~ u64 h7 # u64 6620516959819538809

    // Every block but the last straight from the input; the last one (which
    // may be partial, or empty for an empty input) from a zero-padded copy.
    : i n ( vec_len [u] data )
    : ~ i off 0
    ~ > - n off 128 {
        ( __b2b_compress h0 h1 h2 h3 h4 h5 h6 h7 data off # u64 + off 128 F )
        = off + off 128
    }
    : i rem - n off
    : ( Vec u ) blk ( vec_zeroed [u] 128 )
    : ~ i j 0
    ~ < j rem {
        ( vec_put [u] blk j ( vec_at [u] data + off j ) )
        = j + j 1
    }
    ( __b2b_compress h0 h1 h2 h3 h4 h5 h6 h7 blk 0 # u64 n T )

    // serialize h → 64 little-endian bytes
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( bytes_push_u64_le out h0 )
    ( bytes_push_u64_le out h1 )
    ( bytes_push_u64_le out h2 )
    ( bytes_push_u64_le out h3 )
    ( bytes_push_u64_le out h4 )
    ( bytes_push_u64_le out h5 )
    ( bytes_push_u64_le out h6 )
    ( bytes_push_u64_le out h7 )
    ^ out
}
