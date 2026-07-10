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

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ __b2b_vu64 ( Vec u64 ) v i idx → u64 {
    : ?u64 o ( vec_get [u64] v idx )
    ?? o { T x → { ^ x } F → { ^ # u64 0 } }
}

@ __b2b_vu ( Vec u ) v i idx → i {
    : ?u o ( vec_get [u] v idx )
    ?? o { T x → { ^ # i x } F → { ^ 0 } }
}

// Right-rotate a u64 by c bits (0 < c < 64).
@ __b2b_rotr u64 x i c → u64 {
    : u64 cu # u64 c
    : u64 inv # u64 - 64 c
    ^ | >> x cu << x inv
}

// The eight BLAKE2b IV words (identical to the SHA-512 IV).
@ __b2b_iv → ( Vec u64 ) {
    : ( Vec u64 ) v ( vec_with_cap [u64] 8 )
    ( vec_push [u64] v # u64 7640891576956012808 )
    ( vec_push [u64] v # u64 -4942790177534073029 )
    ( vec_push [u64] v # u64 4354685564936845355 )
    ( vec_push [u64] v # u64 -6534734903238641935 )
    ( vec_push [u64] v # u64 5840696475078001361 )
    ( vec_push [u64] v # u64 -7276294671716946913 )
    ( vec_push [u64] v # u64 2270897969802886507 )
    ( vec_push [u64] v # u64 6620516959819538809 )
    ^ v
}

// The message-word permutation schedule σ, flattened to 12·16 entries
// (round-major). Parsed once from a decimal string.
@ __b2b_sigma → ( Vec u ) {
    : s s ( nurl_str_cat
    `0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 14 10 4 8 9 15 13 6 1 12 0 2 11 7 5 3 11 8 12 0 5 2 15 13 10 14 3 6 7 1 9 4 7 9 3 1 13 12 11 14 2 6 5 10 4 0 15 8 9 0 5 7 2 4 10 15 14 1 11 12 6 8 3 13 2 12 6 10 0 11 8 3 4 13 7 5 15 14 1 9 `
    `12 5 1 15 14 13 4 10 0 7 6 3 9 2 8 11 13 11 7 14 12 1 3 9 5 0 15 4 8 6 2 10 6 15 14 9 11 3 0 8 12 2 13 7 1 4 10 5 10 2 8 4 7 6 1 5 15 11 9 14 3 12 13 0 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 14 10 4 8 9 15 13 6 1 12 0 2 11 7 5 3` )
    : ( Vec u ) out ( vec_new [u] )
    : i n ( nurl_str_len s )
    : ~ i k 0
    : ~ i cur 0
    : ~ b indig F
    ~ < k n {
        : i c ( nurl_str_get s k )
        ? & >= c 48 <= c 57
        { = cur + * cur 10 - c 48 = indig T }
        { ? indig { ( vec_push [u] out # u cur ) = cur 0 = indig F } {} }
        = k + k 1
    }
    ? indig { ( vec_push [u] out # u cur ) } {}
    ^ out
}

// The G mixing function, in place on the working vector v (16 u64).
@ __b2b_g ( Vec u64 ) v i a i b i c i d u64 x u64 y → v {
    : ~ u64 va ( __b2b_vu64 v a )
    : ~ u64 vb ( __b2b_vu64 v b )
    : ~ u64 vc ( __b2b_vu64 v c )
    : ~ u64 vd ( __b2b_vu64 v d )
    = va + + va vb x
    = vd ( __b2b_rotr ^^ vd va 32 )
    = vc + vc vd
    = vb ( __b2b_rotr ^^ vb vc 24 )
    = va + + va vb y
    = vd ( __b2b_rotr ^^ vd va 16 )
    = vc + vc vd
    = vb ( __b2b_rotr ^^ vb vc 63 )
    ( vec_set [u64] v a va )
    ( vec_set [u64] v b vb )
    ( vec_set [u64] v c vc )
    ( vec_set [u64] v d vd )
}

// One message word m[j], the j-th little-endian u64 in `block` at `off`.
@ __b2b_m ( Vec u ) block i off i j → u64 {
    : ?u64 o ( bytes_read_u64_le block + off * j 8 )
    ?? o { T x → { ^ x } F → { ^ # u64 0 } }
}

// Compress one 128-byte block into state h. `t` = bytes hashed through this
// block; `last` != 0 marks the final block.
@ __b2b_compress ( Vec u64 ) h ( Vec u ) block i off u64 t i last ( Vec u ) sigma → v {
    : ( Vec u64 ) iv ( __b2b_iv )
    : ( Vec u64 ) v ( vec_with_cap [u64] 16 )
    : ~ i i 0
    ~ < i 8 { ( vec_push [u64] v ( __b2b_vu64 h i ) ) = i + i 1 }
    = i 0
    ~ < i 8 { ( vec_push [u64] v ( __b2b_vu64 iv i ) ) = i + i 1 }
    // v[12] ^= t_lo ; v[13] ^= t_hi (0 for our sizes) ; v[14] ^= ~0 if last
    ( vec_set [u64] v 12 ^^ ( __b2b_vu64 v 12 ) t )
    ? != last 0 { ( vec_set [u64] v 14 ^^ ( __b2b_vu64 v 14 ) # u64 -1 ) } {}
    // read the 16 message words
    : ( Vec u64 ) m ( vec_with_cap [u64] 16 )
    = i 0
    ~ < i 16 { ( vec_push [u64] m ( __b2b_m block off i ) ) = i + i 1 }
    : ~ i r 0
    ~ < r 12 {
        : i base * r 16
        ( __b2b_g v 0 4 8 12 ( __b2b_vu64 m ( __b2b_vu sigma + base 0 ) ) ( __b2b_vu64 m ( __b2b_vu sigma + base 1 ) ) )
        ( __b2b_g v 1 5 9 13 ( __b2b_vu64 m ( __b2b_vu sigma + base 2 ) ) ( __b2b_vu64 m ( __b2b_vu sigma + base 3 ) ) )
        ( __b2b_g v 2 6 10 14 ( __b2b_vu64 m ( __b2b_vu sigma + base 4 ) ) ( __b2b_vu64 m ( __b2b_vu sigma + base 5 ) ) )
        ( __b2b_g v 3 7 11 15 ( __b2b_vu64 m ( __b2b_vu sigma + base 6 ) ) ( __b2b_vu64 m ( __b2b_vu sigma + base 7 ) ) )
        ( __b2b_g v 0 5 10 15 ( __b2b_vu64 m ( __b2b_vu sigma + base 8 ) ) ( __b2b_vu64 m ( __b2b_vu sigma + base 9 ) ) )
        ( __b2b_g v 1 6 11 12 ( __b2b_vu64 m ( __b2b_vu sigma + base 10 ) ) ( __b2b_vu64 m ( __b2b_vu sigma + base 11 ) ) )
        ( __b2b_g v 2 7 8 13 ( __b2b_vu64 m ( __b2b_vu sigma + base 12 ) ) ( __b2b_vu64 m ( __b2b_vu sigma + base 13 ) ) )
        ( __b2b_g v 3 4 9 14 ( __b2b_vu64 m ( __b2b_vu sigma + base 14 ) ) ( __b2b_vu64 m ( __b2b_vu sigma + base 15 ) ) )
        = r + r 1
    }
    = i 0
    ~ < i 8 {
        ( vec_set [u64] h i ^^ ( __b2b_vu64 h i ) ^^ ( __b2b_vu64 v i ) ( __b2b_vu64 v + i 8 ) )
        = i + i 1
    }
    ( vec_free [u64] iv )
    ( vec_free [u64] v )
    ( vec_free [u64] m )
}

@ __b2b_zeros i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i i 0
    ~ < i n { ( vec_push [u] v # u 0 ) = i + i 1 }
    ^ v
}

@ blake2b512_pure ( Vec u ) data → ( Vec u ) {
    : ( Vec u ) sigma ( __b2b_sigma )
    : ( Vec u64 ) h ( __b2b_iv )
    // h[0] ^= 0x01010040 (params: digest length 64, no key, fanout/depth 1)
    ( vec_set [u64] h 0 ^^ ( __b2b_vu64 h 0 ) # u64 16842816 )
    : i n ( vec_len [u] data )
    ? == n 0 {
        : ( Vec u ) blk ( __b2b_zeros 128 )
        ( __b2b_compress h blk 0 # u64 0 1 sigma )
        ( vec_free [u] blk )
    } {
        : ~ i off 0
        : ~ u64 t # u64 0
        : ~ b done F
        ~ ! done {
            : i remain - n off
            ? > remain 128 {
                = t + t # u64 128
                ( __b2b_compress h data off t 0 sigma )
                = off + off 128
            } {
                = t + t # u64 remain
                : ( Vec u ) blk ( __b2b_zeros 128 )
                : ~ i j 0
                ~ < j remain {
                    ( vec_set [u] blk j # u ( __b2b_vu data + off j ) )
                    = j + j 1
                }
                ( __b2b_compress h blk 0 t 1 sigma )
                ( vec_free [u] blk )
                = done T
            }
        }
    }
    // serialize h → 64 little-endian bytes
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    : ~ i i 0
    ~ < i 8 { ( bytes_push_u64_le out ( __b2b_vu64 h i ) ) = i + i 1 }
    ( vec_free [u64] h )
    ( vec_free [u] sigma )
    ^ out
}
