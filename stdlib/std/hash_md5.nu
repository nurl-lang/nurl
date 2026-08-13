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

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// ── Round constants T_i = floor(2^32 · |sin(i + 1)|), per RFC 1321
//    §3.4. Built once per call into a Vec[u32]; 64-deep table.

@ __md5_K → ( Vec u32 ) {
    : ( Vec u32 ) k ( vec_with_cap [u32] 64 )
    ( vec_push [u32] k # u32 3614090360 )
    ( vec_push [u32] k # u32 3905402710 )
    ( vec_push [u32] k # u32 606105819 )
    ( vec_push [u32] k # u32 3250441966 )
    ( vec_push [u32] k # u32 4118548399 )
    ( vec_push [u32] k # u32 1200080426 )
    ( vec_push [u32] k # u32 2821735955 )
    ( vec_push [u32] k # u32 4249261313 )
    ( vec_push [u32] k # u32 1770035416 )
    ( vec_push [u32] k # u32 2336552879 )
    ( vec_push [u32] k # u32 4294925233 )
    ( vec_push [u32] k # u32 2304563134 )
    ( vec_push [u32] k # u32 1804603682 )
    ( vec_push [u32] k # u32 4254626195 )
    ( vec_push [u32] k # u32 2792965006 )
    ( vec_push [u32] k # u32 1236535329 )
    ( vec_push [u32] k # u32 4129170786 )
    ( vec_push [u32] k # u32 3225465664 )
    ( vec_push [u32] k # u32 643717713 )
    ( vec_push [u32] k # u32 3921069994 )
    ( vec_push [u32] k # u32 3593408605 )
    ( vec_push [u32] k # u32 38016083 )
    ( vec_push [u32] k # u32 3634488961 )
    ( vec_push [u32] k # u32 3889429448 )
    ( vec_push [u32] k # u32 568446438 )
    ( vec_push [u32] k # u32 3275163606 )
    ( vec_push [u32] k # u32 4107603335 )
    ( vec_push [u32] k # u32 1163531501 )
    ( vec_push [u32] k # u32 2850285829 )
    ( vec_push [u32] k # u32 4243563512 )
    ( vec_push [u32] k # u32 1735328473 )
    ( vec_push [u32] k # u32 2368359562 )
    ( vec_push [u32] k # u32 4294588738 )
    ( vec_push [u32] k # u32 2272392833 )
    ( vec_push [u32] k # u32 1839030562 )
    ( vec_push [u32] k # u32 4259657740 )
    ( vec_push [u32] k # u32 2763975236 )
    ( vec_push [u32] k # u32 1272893353 )
    ( vec_push [u32] k # u32 4139469664 )
    ( vec_push [u32] k # u32 3200236656 )
    ( vec_push [u32] k # u32 681279174 )
    ( vec_push [u32] k # u32 3936430074 )
    ( vec_push [u32] k # u32 3572445317 )
    ( vec_push [u32] k # u32 76029189 )
    ( vec_push [u32] k # u32 3654602809 )
    ( vec_push [u32] k # u32 3873151461 )
    ( vec_push [u32] k # u32 530742520 )
    ( vec_push [u32] k # u32 3299628645 )
    ( vec_push [u32] k # u32 4096336452 )
    ( vec_push [u32] k # u32 1126891415 )
    ( vec_push [u32] k # u32 2878612391 )
    ( vec_push [u32] k # u32 4237533241 )
    ( vec_push [u32] k # u32 1700485571 )
    ( vec_push [u32] k # u32 2399980690 )
    ( vec_push [u32] k # u32 4293915773 )
    ( vec_push [u32] k # u32 2240044497 )
    ( vec_push [u32] k # u32 1873313359 )
    ( vec_push [u32] k # u32 4264355552 )
    ( vec_push [u32] k # u32 2734768916 )
    ( vec_push [u32] k # u32 1309151649 )
    ( vec_push [u32] k # u32 4149444226 )
    ( vec_push [u32] k # u32 3174756917 )
    ( vec_push [u32] k # u32 718787259 )
    ( vec_push [u32] k # u32 3951481745 )
    ^ k
}

// ── Per-round left-rotate counts, four 4-element repeating cycles
//    per group of 16 rounds. Bytes fit in u so we use Vec[u].

@ __md5_S → ( Vec u ) {
    : ( Vec u ) s ( vec_with_cap [u] 64 )
    : ~ i g 0
    ~ < g 4 {
        // groups: 0/16/32/48
        : i base_off * g 16
        : ~ i j 0
        ~ < j 16 {
            : i mod4 & j 3
            : i sval ? == g 0
            ? == mod4 0 7 ? == mod4 1 12 ? == mod4 2 17 22
            ? == g 1
            ? == mod4 0 5 ? == mod4 1 9 ? == mod4 2 14 20
            ? == g 2
            ? == mod4 0 4 ? == mod4 1 11 ? == mod4 2 16 23
            ? == mod4 0 6 ? == mod4 1 10 ? == mod4 2 15 21
            ( vec_push [u] s # u sval )
            = j + j 1
        }
        = g + g 1
    }
    ^ s
}

// ── Helpers ────────────────────────────────────────────────────────

// Bounds-checked vec_get unwrap; returns 0 when out of range (caller
// guarantees in-bounds, so the F-arm is dead code).
@ __md5_vu32 ( Vec u32 ) v i idx → u32 {
    : ?u32 o ( vec_get [u32] v idx )
    ?? o { T x → { ^ x } F → { ^ # u32 0 } }
}

@ __md5_vu8 ( Vec u ) v i idx → i {
    : ?u o ( vec_get [u] v idx )
    ?? o { T x → { ^ # i x } F → { ^ 0 } }
}

// Left-rotate u32 by c bits (0 ≤ c < 32). The shift count is
// pre-cast to u32 so LLVM emits `shl i32 %x, %c` (both operands
// matching width); the shifts are then `shl` (left) / `lshr`
// (right, logical because operand is u32) and the `|` combines.
@ __md5_rotl u32 x i c → u32 {
    // One `rol` instruction via the compiler's funnel-shift primitive,
    // rather than a shift pair, an `or` and the two intermediate
    // values they need materialised — see __sha256_rotr for the full
    // note. Every ISA NURL targets has the instruction.
    ^ # u32 ( nurl_rotl32 # u64 x # u64 c )
}

// ── Transform: process one 64-byte block starting at `offset`.
//    state is a 4-element Vec[u32]; mutated in place via vec_set.

@ __md5_transform ( Vec u32 ) state ( Vec u ) block i offset ( Vec u32 ) K ( Vec u ) S → v {
    // Decode 16 little-endian u32 words from the block.
    : ( Vec u32 ) m ( vec_with_cap [u32] 16 )
    : ~ i wi 0
    ~ < wi 16 {
        : ?u32 wo ( bytes_read_u32_le block + offset * wi 4 )
        : u32 w ?? wo { T x → x F → # u32 0 }
        ( vec_push [u32] m w )
        = wi + wi 1
    }

    : ~ u32 a ( __md5_vu32 state 0 )
    : ~ u32 b ( __md5_vu32 state 1 )
    : ~ u32 c ( __md5_vu32 state 2 )
    : ~ u32 d ( __md5_vu32 state 3 )

    : ~ i ri 0
    ~ < ri 64 {
        : ~ u32 f # u32 0
        : ~ i g 0
        ? < ri 16 {
            = f | & b c & ~ b d
            = g ri
        } {
            ? < ri 32 {
                = f | & d b & ~ d c
                = g & + * 5 ri 1 15
            } {
                ? < ri 48 {
                    = f ^^ ^^ b c d
                    = g & + * 3 ri 5 15
                } {
                    = f ^^ c | b ~ d
                    = g & * 7 ri 15
                }
            }
        }
        : u32 ki ( __md5_vu32 K ri )
        : u32 mg ( __md5_vu32 m g )
        : u32 x + + + a f ki mg
        : i si ( __md5_vu8 S ri )
        : u32 tmp d
        = d c
        = c b
        = b + b ( __md5_rotl x si )
        = a tmp
        = ri + ri 1
    }

    : u32 s0 ( __md5_vu32 state 0 )
    : u32 s1 ( __md5_vu32 state 1 )
    : u32 s2 ( __md5_vu32 state 2 )
    : u32 s3 ( __md5_vu32 state 3 )
    : b _0 ( vec_set [u32] state 0 + s0 a )
    : b _1 ( vec_set [u32] state 1 + s1 b )
    : b _2 ( vec_set [u32] state 2 + s2 c )
    : b _3 ( vec_set [u32] state 3 + s3 d )

    ( vec_free [u32] m )
}

// ── Public entry — same shape as runtime-backed `md5_bytes`. ───────

@ md5_pure ( Vec u ) data → ( Vec u ) {
    : ( Vec u32 ) K ( __md5_K )
    : ( Vec u ) S ( __md5_S )

    // State: A, B, C, D per RFC 1321 §3.3.
    : ( Vec u32 ) state ( vec_with_cap [u32] 4 )
    ( vec_push [u32] state # u32 1732584193 )  // 0x67452301
    ( vec_push [u32] state # u32 4023233417 )  // 0xefcdab89
    ( vec_push [u32] state # u32 2562383102 )  // 0x98badcfe
    ( vec_push [u32] state # u32 271733878 )  // 0x10325476

    : i n ( vec_len [u] data )

    // Process complete 64-byte blocks straight from the input.
    : ~ i off 0
    ~ <= + off 64 n {
        ( __md5_transform state data off K S )
        = off + off 64
    }

    // Build the tail block: leftover bytes + 0x80 + zero padding +
    // 64-bit little-endian bit-length, transformed as 1 or 2 blocks.
    : ( Vec u ) tail ( vec_with_cap [u] 128 )
    : ~ i ti off
    ~ < ti n {
        : i bv ( __md5_vu8 data ti )
        ( vec_push [u] tail # u & bv 255 )
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
        ( __md5_transform state tail toff K S )
        = toff + toff 64
    }
    ( vec_free [u] tail )

    // Serialise state[0..4] as 16 little-endian bytes.
    : ( Vec u ) out ( vec_with_cap [u] 16 )
    : ~ i si 0
    ~ < si 4 {
        : u32 sv ( __md5_vu32 state si )
        ( vec_push [u] out # u & # i sv 255 )
        ( vec_push [u] out # u & >> # i sv 8 255 )
        ( vec_push [u] out # u & >> # i sv 16 255 )
        ( vec_push [u] out # u & >> # i sv 24 255 )
        = si + si 1
    }

    ( vec_free [u32] state )
    ( vec_free [u32] K )
    ( vec_free [u] S )
    ^ out
}
