// stdlib/std/hash_sha1.nu — RFC 3174 SHA-1 in pure NURL.
//
// Algorithm strength: SHA-1 is collision-broken and MUST NOT be used
// for new security-sensitive authentication. Provided for protocols
// that mandate it — WebSocket handshake `Sec-WebSocket-Accept` per
// RFC 6455 §4.2.2, git object IDs, legacy APIs.
//
// API:
//   ( sha1_pure ( Vec u ) data ) → ( Vec u )   20-byte digest (owned)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// Bounds-checked unwrappers — caller guarantees index in range, the
// F-arm is dead code.
@ __sha1_vu32 ( Vec u32 ) v i idx → u32 {
    : ?u32 o ( vec_get [u32] v idx )
    ?? o { T x → { ^ x } F → { ^ # u32 0 } }
}

@ __sha1_vu8 ( Vec u ) v i idx → i {
    : ?u o ( vec_get [u] v idx )
    ?? o { T x → { ^ # i x } F → { ^ 0 } }
}

// Left-rotate u32 by c bits (0 < c < 32).
@ __sha1_rotl u32 x i c → u32 {
    : u32 cu # u32 c
    : u32 inv # u32 - 32 c
    ^ | << x cu >> x inv
}

// ── Round constants for the four 20-round groups ───────────────────

@ __sha1_K i group → u32 {
    ? == group 0 { ^ # u32 1518500249 } {}  // 0x5A827999
    ? == group 1 { ^ # u32 1859775393 } {}  // 0x6ED9EBA1
    ? == group 2 { ^ # u32 2400959708 } {}  // 0x8F1BBCDC (signed: -1894007588)
    ^ # u32 3395469782  // 0xCA62C1D6
}

// ── Transform: one 64-byte block. Mutates `state` (5 × u32) in place.

@ __sha1_transform ( Vec u32 ) state ( Vec u ) block i offset → v {
    // Decode 16 big-endian u32 words; expand to 80 via the SHA-1
    // message schedule.
    : ( Vec u32 ) w ( vec_with_cap [u32] 80 )
    : ~ i wi 0
    ~ < wi 16 {
        : ?u32 wo ( bytes_read_u32_be block + offset * wi 4 )
        : u32 wv ?? wo { T x → x F → # u32 0 }
        ( vec_push [u32] w wv )
        = wi + wi 1
    }
    ~ < wi 80 {
        : u32 w3 ( __sha1_vu32 w - wi 3 )
        : u32 w8 ( __sha1_vu32 w - wi 8 )
        : u32 w14 ( __sha1_vu32 w - wi 14 )
        : u32 w16 ( __sha1_vu32 w - wi 16 )
        : u32 xv ^^ ^^ ^^ w3 w8 w14 w16
        ( vec_push [u32] w ( __sha1_rotl xv 1 ) )
        = wi + wi 1
    }

    : ~ u32 a ( __sha1_vu32 state 0 )
    : ~ u32 b ( __sha1_vu32 state 1 )
    : ~ u32 c ( __sha1_vu32 state 2 )
    : ~ u32 d ( __sha1_vu32 state 3 )
    : ~ u32 e ( __sha1_vu32 state 4 )

    : ~ i ri 0
    ~ < ri 80 {
        : ~ u32 f # u32 0
        : i grp / ri 20
        ? == grp 0 { = f | & b c & ~ b d } {
            ? == grp 1 { = f ^^ ^^ b c d } {
                ? == grp 2 { = f | | & b c & b d & c d } {
                    = f ^^ ^^ b c d
                }
            }
        }
        : u32 kv ( __sha1_K grp )
        : u32 wv ( __sha1_vu32 w ri )
        : u32 t + + + + ( __sha1_rotl a 5 ) f e kv wv
        = e d
        = d c
        = c ( __sha1_rotl b 30 )
        = b a
        = a t
        = ri + ri 1
    }

    : u32 s0 ( __sha1_vu32 state 0 )
    : u32 s1 ( __sha1_vu32 state 1 )
    : u32 s2 ( __sha1_vu32 state 2 )
    : u32 s3 ( __sha1_vu32 state 3 )
    : u32 s4 ( __sha1_vu32 state 4 )
    : b _0 ( vec_set [u32] state 0 + s0 a )
    : b _1 ( vec_set [u32] state 1 + s1 b )
    : b _2 ( vec_set [u32] state 2 + s2 c )
    : b _3 ( vec_set [u32] state 3 + s3 d )
    : b _4 ( vec_set [u32] state 4 + s4 e )

    ( vec_free [u32] w )
}

// ── Public entry — same shape as `md5_pure`. ──────────────────────

@ sha1_pure ( Vec u ) data → ( Vec u ) {
    : ( Vec u32 ) state ( vec_with_cap [u32] 5 )
    ( vec_push [u32] state # u32 1732584193 )  // 0x67452301
    ( vec_push [u32] state # u32 4023233417 )  // 0xEFCDAB89
    ( vec_push [u32] state # u32 2562383102 )  // 0x98BADCFE
    ( vec_push [u32] state # u32 271733878 )  // 0x10325476
    ( vec_push [u32] state # u32 3285377520 )  // 0xC3D2E1F0

    : i n ( vec_len [u] data )

    : ~ i off 0
    ~ <= + off 64 n {
        ( __sha1_transform state data off )
        = off + off 64
    }

    // Tail: leftover bytes + 0x80 + zero pad + 64-bit BIG-endian length.
    : ( Vec u ) tail ( vec_with_cap [u] 128 )
    : ~ i ti off
    ~ < ti n {
        : i bv ( __sha1_vu8 data ti )
        ( vec_push [u] tail # u & bv 255 )
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
        ( __sha1_transform state tail toff )
        = toff + toff 64
    }
    ( vec_free [u] tail )

    // Serialise state[0..5] as 20 big-endian bytes.
    : ( Vec u ) out ( vec_with_cap [u] 20 )
    : ~ i si 0
    ~ < si 5 {
        : u32 sv ( __sha1_vu32 state si )
        : i siv # i sv
        ( vec_push [u] out # u & >> siv 24 255 )
        ( vec_push [u] out # u & >> siv 16 255 )
        ( vec_push [u] out # u & >> siv 8 255 )
        ( vec_push [u] out # u & siv 255 )
        = si + si 1
    }

    ( vec_free [u32] state )
    ^ out
}
