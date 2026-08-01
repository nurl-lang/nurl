// stdlib/std/aes_gcm.nu — pure-NURL AES-128/256-GCM AEAD (NIST SP 800-38D),
// no OpenSSL. This is the TLS_AES_128_GCM_SHA256 record protection — the
// mandatory-to-implement TLS 1.3 cipher — so the client can talk to
// servers that only offer AES.
//
//   ( aes128_gcm_encrypt key nonce aad pt )     → ( Vec u )  ct||tag
//   ( aes128_gcm_decrypt key nonce aad ct_tag ) → ?( Vec u )  None if forged
//   ( aes256_gcm_encrypt key nonce aad pt )     → ( Vec u )  ct||tag
//   ( aes256_gcm_decrypt key nonce aad ct_tag ) → ?( Vec u )  None if forged
//
//   key = 16 or 32 bytes, nonce = 12 bytes.
//
// ── Why this file looks the way it does ───────────────────────────
//
// Constant time is not negotiable here: a table-driven AES indexes memory
// with key-dependent bytes and leaks the key through the cache, which is
// the whole reason CPUs grew AES instructions. NURL has no AES-NI path,
// so the constant-time requirement has to be met in software.
//
// The obvious way — compute the S-box algebraically per byte, as
// SubBytes(x) = Affine(x^254) — is constant-time and was what this file
// did. It also costs about a thousand operations per byte, which put
// AES-GCM at 0.3 MB/s against ChaCha20-Poly1305's 370: a TLS peer that
// insisted on AES made an 8 MB download take half a minute.
//
// So the block cipher is BITSLICED instead (the technique BearSSL's
// `aes_ct64` uses, and this is a port of it — Thomas Pornin, MIT):
// the state is transposed so each of eight 64-bit words holds one bit
// position of 64 bytes, and the S-box becomes Boyar and Peralta's
// 113-gate straight-line boolean circuit evaluated on those words. One
// circuit evaluation substitutes 64 bytes at once, so the S-box costs
// under two operations per byte instead of a thousand, with no table and
// no data-dependent branch anywhere. Four blocks travel together, which
// is exactly what CTR mode wants.
//
// GHASH gets the same treatment. Multiplying in GF(2^128) bit by bit is
// 128 iterations of a 16-byte shift-and-mask; instead this uses BearSSL's
// `ghash_ctmul64` — carry-less multiplication built out of ordinary
// 64-bit integer multiplies, by splitting each operand into four
// bit-groups so no carry can cross a group boundary, then Karatsuba over
// the two halves. Constant-time on any CPU whose integer multiplier is
// (every mainstream 64-bit core; some small in-order ARM cores have
// data-dependent multiply latency and would need the bitwise version).
//
// The key schedule is left as the per-byte algebraic S-box below: it runs
// once per key, costs about 44 S-box evaluations, and is not worth
// bitslicing.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

@ __aes_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 }
}

// ── Key schedule (cold path): algebraic constant-time S-box ───────
// SubBytes(x) = Affine(x^{-1} in GF(2^8)). Both the GF multiply and the
// fixed-exponent inversion are branchless in the data, so duration is
// independent of the key. Verified to match the reference S-box on all
// 256 inputs. Used only by the key expansion — the block cipher itself
// uses the bitsliced circuit further down.

// Constant-time GF(2^8) multiply (AES field, reduction polynomial 0x11b).
@ __gf_mul i a i b → i {
    : ~ i p 0
    : ~ i aa & a 255
    : ~ i bb & b 255
    : ~ i k 0
    ~ < k 8 {
        : i m & 1 bb
        = p ^^ p & aa - 0 m  // add aa iff low bit of bb set (mask)
        : i hi & 1 >> aa 7
        = aa & 255 ^^ << aa 1 & 27 - 0 hi  // xtime(aa), branchless reduction
        = bb >> bb 1
        = k + k 1
    }
    ^ & p 255
}

// Multiplicative inverse in GF(2^8): x^254 (= x^{-1}; 0 maps to 0). The
// exponent 254 is a constant, so the square/multiply pattern is fixed and
// independent of the secret x.
@ __gf_inv i x → i {
    : i xx & x 255
    : ~ i r 1
    : ~ i bit 7
    ~ >= bit 0 {
        = r ( __gf_mul r r )
        ? != 0 & 1 >> 254 bit { = r ( __gf_mul r xx ) } {}
        = bit - bit 1
    }
    ^ r
}

@ __rotl8 i x i n → i { ^ & 255 | << x n >> & 255 x - 8 n }

// SubBytes(x) — constant-time. s = inv ⊕ rotl(inv,1..4) ⊕ 0x63.
@ __aes_sbox_ct i x → i {
    : i b0 ( __gf_inv & x 255 )
    ^ & 255 ^^ ^^ ^^ ^^ ^^ b0 ( __rotl8 b0 1 ) ( __rotl8 b0 2 ) ( __rotl8 b0 3 ) ( __rotl8 b0 4 ) 99
}

// AES-128 key expansion → 176 bytes (11 round keys).
@ __aes128_expand ( Vec u ) key → ( Vec u ) {
    : ( Vec u ) w ( vec_with_cap [u] 176 )
    : ~ i i 0
    ~ < i 16 { ( vec_push [u] w # u ( __aes_bget key i ) ) = i + i 1 }
    : ( Vec u ) rcon ?? ( bytes_from_hex `01020408102040801b36` ) { T v → v F _ → ( vec_new [u] ) }
    : ~ i n 16
    : ~ i rc 0
    ~ < n 176 {
        : ~ i t0 ( __aes_bget w - n 4 )
        : ~ i t1 ( __aes_bget w - n 3 )
        : ~ i t2 ( __aes_bget w - n 2 )
        : ~ i t3 ( __aes_bget w - n 1 )
        ? == % n 16 0 {
            // RotWord + SubWord + Rcon
            : i a ( __aes_sbox_ct t1 )
            : i b ( __aes_sbox_ct t2 )
            : i c ( __aes_sbox_ct t3 )
            : i d ( __aes_sbox_ct t0 )
            = t0 ^^ a ( __aes_bget rcon rc )
            = t1 b
            = t2 c
            = t3 d
            = rc + rc 1
        } {}
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 16 ) t0 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 15 ) t1 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 14 ) t2 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 13 ) t3 )
        = n + n 4
    }
    ( vec_free [u] rcon )
    ^ w
}

// AES-256 key expansion → 240 bytes (15 round keys). Nk = 8: an extra
// SubWord every 8th word (the i%8 == 4 case) on top of the 128 schedule.
@ __aes256_expand ( Vec u ) key → ( Vec u ) {
    : ( Vec u ) w ( vec_with_cap [u] 240 )
    : ~ i i 0
    ~ < i 32 { ( vec_push [u] w # u ( __aes_bget key i ) ) = i + i 1 }
    : ( Vec u ) rcon ?? ( bytes_from_hex `0102040810204080` ) { T v → v F _ → ( vec_new [u] ) }
    : ~ i n 32
    : ~ i rc 0
    ~ < n 240 {
        : ~ i t0 ( __aes_bget w - n 4 )
        : ~ i t1 ( __aes_bget w - n 3 )
        : ~ i t2 ( __aes_bget w - n 2 )
        : ~ i t3 ( __aes_bget w - n 1 )
        ? == % n 32 0 {
            // RotWord + SubWord + Rcon
            : i a ( __aes_sbox_ct t1 )
            : i b ( __aes_sbox_ct t2 )
            : i c ( __aes_sbox_ct t3 )
            : i d ( __aes_sbox_ct t0 )
            = t0 ^^ a ( __aes_bget rcon rc )
            = t1 b
            = t2 c
            = t3 d
            = rc + rc 1
        } {
            ? == % n 32 16 {
                // SubWord only (no RotWord, no Rcon)
                = t0 ( __aes_sbox_ct t0 )
                = t1 ( __aes_sbox_ct t1 )
                = t2 ( __aes_sbox_ct t2 )
                = t3 ( __aes_sbox_ct t3 )
            } {}
        }
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 32 ) t0 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 31 ) t1 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 30 ) t2 )
        ( vec_push [u] w # u ^^ ( __aes_bget w - n 29 ) t3 )
        = n + n 4
    }
    ( vec_free [u] rcon )
    ^ w
}

// Pick the expanded round keys for a 16- or 32-byte key.
@ __aes_expand ( Vec u ) key → ( Vec u ) {
    ? == ( vec_len [u] key ) 32 { ^ ( __aes256_expand key ) } { ^ ( __aes128_expand key ) }
}

// Round count for a 16- or 32-byte key.
@ __aes_nr ( Vec u ) key → i { ? == ( vec_len [u] key ) 32 { ^ 14 } { ^ 10 } }

// ── Raw-memory word helpers ──────────────────────────────────────
// The bitsliced core works on 64-bit words held in locals; buffers are
// plain malloc'd memory addressed through `nurl_peek` / `nurl_poke`
// (8-byte words) or `.` (bytes), never through bounds-checked Vec
// accessors — a 16 KB record is a thousand blocks and every checked call
// would be paid a thousand times.

// Little-endian 32-bit load. The AES state and the key schedule both use
// the little-endian word convention throughout, so this is the only byte
// order the cipher core ever sees.
@ __ld32le * u p i off → u64 {
    ^ # u64 | | | # i . p off << # i . p + off 1 8 << # i . p + off 2 16 << # i . p + off 3 24
}

// Little-endian 32-bit store (writes the low 4 bytes of `w`).
@ __st32le * u p i off u64 w → v {
    = . p off # u # i & w 255
    = . p + off 1 # u # i & >> w 8 255
    = . p + off 2 # u # i & >> w 16 255
    = . p + off 3 # u # i & >> w 24 255
}

// ── Bitslicing ───────────────────────────────────────────────────
// `ortho` is the bit-matrix transpose that turns four blocks laid out as
// bytes into eight bit-plane words and back. It is its own inverse.

// One transpose step: exchange the bit groups selected by `cl` / `ch`
// between the words at `ia` and `ib`.
@ __swapn s q i base i ia i ib u64 cl u64 ch i sh → v {
    : u64 a # u64 ( nurl_peek q + base ia )
    : u64 b # u64 ( nurl_peek q + base ib )
    ( nurl_poke q + base ia # i | & a cl << & b cl sh )
    ( nurl_poke q + base ib # i | >> & a ch sh & b ch )
}

@ __ortho8 s q i base → v {
    ( __swapn q base 0 1 0x5555555555555555 0xAAAAAAAAAAAAAAAA 1 )
    ( __swapn q base 2 3 0x5555555555555555 0xAAAAAAAAAAAAAAAA 1 )
    ( __swapn q base 4 5 0x5555555555555555 0xAAAAAAAAAAAAAAAA 1 )
    ( __swapn q base 6 7 0x5555555555555555 0xAAAAAAAAAAAAAAAA 1 )
    ( __swapn q base 0 2 0x3333333333333333 0xCCCCCCCCCCCCCCCC 2 )
    ( __swapn q base 1 3 0x3333333333333333 0xCCCCCCCCCCCCCCCC 2 )
    ( __swapn q base 4 6 0x3333333333333333 0xCCCCCCCCCCCCCCCC 2 )
    ( __swapn q base 5 7 0x3333333333333333 0xCCCCCCCCCCCCCCCC 2 )
    ( __swapn q base 0 4 0x0F0F0F0F0F0F0F0F 0xF0F0F0F0F0F0F0F0 4 )
    ( __swapn q base 1 5 0x0F0F0F0F0F0F0F0F 0xF0F0F0F0F0F0F0F0 4 )
    ( __swapn q base 2 6 0x0F0F0F0F0F0F0F0F 0xF0F0F0F0F0F0F0F0 4 )
    ( __swapn q base 3 7 0x0F0F0F0F0F0F0F0F 0xF0F0F0F0F0F0F0F0 4 )
}

// Spread one block's four state words across the low and high halves of
// the bitslice layout: block `idx` lives in words `idx` and `idx + 4`.
@ __ilv_in s q i idx u64 w0 u64 w1 u64 w2 u64 w3 → v {
    : ~ u64 x0 w0
    : ~ u64 x1 w1
    : ~ u64 x2 w2
    : ~ u64 x3 w3
    = x0 & | x0 << x0 16 0x0000FFFF0000FFFF
    = x1 & | x1 << x1 16 0x0000FFFF0000FFFF
    = x2 & | x2 << x2 16 0x0000FFFF0000FFFF
    = x3 & | x3 << x3 16 0x0000FFFF0000FFFF
    = x0 & | x0 << x0 8 0x00FF00FF00FF00FF
    = x1 & | x1 << x1 8 0x00FF00FF00FF00FF
    = x2 & | x2 << x2 8 0x00FF00FF00FF00FF
    = x3 & | x3 << x3 8 0x00FF00FF00FF00FF
    ( nurl_poke q idx # i | x0 << x2 8 )
    ( nurl_poke q + idx 4 # i | x1 << x3 8 )
}

// The inverse: one block's two words back out to 16 bytes at `p + off`.
@ __ilv_out * u p i off u64 q0 u64 q1 → v {
    : ~ u64 x0 & q0 0x00FF00FF00FF00FF
    : ~ u64 x1 & q1 0x00FF00FF00FF00FF
    : ~ u64 x2 & >> q0 8 0x00FF00FF00FF00FF
    : ~ u64 x3 & >> q1 8 0x00FF00FF00FF00FF
    = x0 & | x0 >> x0 8 0x0000FFFF0000FFFF
    = x1 & | x1 >> x1 8 0x0000FFFF0000FFFF
    = x2 & | x2 >> x2 8 0x0000FFFF0000FFFF
    = x3 & | x3 >> x3 8 0x0000FFFF0000FFFF
    ( __st32le p off | x0 >> x0 16 )
    ( __st32le p + off 4 | x1 >> x1 16 )
    ( __st32le p + off 8 | x2 >> x2 16 )
    ( __st32le p + off 12 | x3 >> x3 16 )
}

// Round keys in bitsliced form: 8 words per round, the same key material
// replicated into all four block slots. Runs once per key. The caller
// owns the returned buffer and frees it with `nurl_free`.
@ __skey_bitslice ( Vec u ) rk i nr → s {
    : s sk ( nurl_zalloc * 8 * 8 + nr 1 )
    : s q ( nurl_zalloc 64 )
    : *u rkp ( vec_data [u] rk )
    : ~ i r 0
    ~ <= r nr {
        : i o * r 16
        ( __ilv_in q 0 ( __ld32le rkp o ) ( __ld32le rkp + o 4 ) ( __ld32le rkp + o 8 ) ( __ld32le rkp + o 12 ) )
        // All four slots hold the same round key.
        ( nurl_poke q 1 ( nurl_peek q 0 ) )
        ( nurl_poke q 2 ( nurl_peek q 0 ) )
        ( nurl_poke q 3 ( nurl_peek q 0 ) )
        ( nurl_poke q 5 ( nurl_peek q 4 ) )
        ( nurl_poke q 6 ( nurl_peek q 4 ) )
        ( nurl_poke q 7 ( nurl_peek q 4 ) )
        ( __ortho8 q 0 )
        : i base * r 8
        : ~ i k 0
        ~ < k 8 { ( nurl_poke sk + base k ( nurl_peek q k ) ) = k + k 1 }
        = r + r 1
    }
    ( nurl_free q )
    ^ sk
}

// ── The block cipher ─────────────────────────────────────────────
// Encrypt four 16-byte blocks at `inp` into `outp`. `q` is a caller-owned
// 8-word scratch buffer, allocated once per AEAD call rather than once
// per block.
//
// Everything between the two transposes is held in locals so the register
// allocator can see it: the S-box circuit alone is 113 gates, and routing
// each of them through memory would cost more than the gates. This is why
// the whole cipher is one function instead of the six the C reference
// splits it into — NURL returns one value, and the round state is eight.
@ __aes_ct64_enc4 * u inp * u outp s skey i nr s q → v {
    ( __ilv_in q 0 ( __ld32le inp 0 ) ( __ld32le inp 4 ) ( __ld32le inp 8 ) ( __ld32le inp 12 ) )
    ( __ilv_in q 1 ( __ld32le inp 16 ) ( __ld32le inp 20 ) ( __ld32le inp 24 ) ( __ld32le inp 28 ) )
    ( __ilv_in q 2 ( __ld32le inp 32 ) ( __ld32le inp 36 ) ( __ld32le inp 40 ) ( __ld32le inp 44 ) )
    ( __ilv_in q 3 ( __ld32le inp 48 ) ( __ld32le inp 52 ) ( __ld32le inp 56 ) ( __ld32le inp 60 ) )
    ( __ortho8 q 0 )

    : ~ u64 q0 # u64 ( nurl_peek q 0 )
    : ~ u64 q1 # u64 ( nurl_peek q 1 )
    : ~ u64 q2 # u64 ( nurl_peek q 2 )
    : ~ u64 q3 # u64 ( nurl_peek q 3 )
    : ~ u64 q4 # u64 ( nurl_peek q 4 )
    : ~ u64 q5 # u64 ( nurl_peek q 5 )
    : ~ u64 q6 # u64 ( nurl_peek q 6 )
    : ~ u64 q7 # u64 ( nurl_peek q 7 )

    // AddRoundKey, round 0.
    = q0 ^^ q0 # u64 ( nurl_peek skey 0 )
    = q1 ^^ q1 # u64 ( nurl_peek skey 1 )
    = q2 ^^ q2 # u64 ( nurl_peek skey 2 )
    = q3 ^^ q3 # u64 ( nurl_peek skey 3 )
    = q4 ^^ q4 # u64 ( nurl_peek skey 4 )
    = q5 ^^ q5 # u64 ( nurl_peek skey 5 )
    = q6 ^^ q6 # u64 ( nurl_peek skey 6 )
    = q7 ^^ q7 # u64 ( nurl_peek skey 7 )

    // Rounds 1..nr. The last round skips MixColumns; the round number is
    // public, so branching on it leaks nothing.
    : ~ i round 1
    ~ <= round nr {
        // ── SubBytes: Boyar–Peralta's 113-gate circuit, evaluated on the
        // eight bit planes at once (64 S-box substitutions per pass).
        : u64 x0 q7
        : u64 x1 q6
        : u64 x2 q5
        : u64 x3 q4
        : u64 x4 q3
        : u64 x5 q2
        : u64 x6 q1
        : u64 x7 q0

        : u64 y14 ^^ x3 x5
        : u64 y13 ^^ x0 x6
        : u64 y9 ^^ x0 x3
        : u64 y8 ^^ x0 x5
        : u64 t0 ^^ x1 x2
        : u64 y1 ^^ t0 x7
        : u64 y4 ^^ y1 x3
        : u64 y12 ^^ y13 y14
        : u64 y2 ^^ y1 x0
        : u64 y5 ^^ y1 x6
        : u64 y3 ^^ y5 y8
        : u64 t1 ^^ x4 y12
        : u64 y15 ^^ t1 x5
        : u64 y20 ^^ t1 x1
        : u64 y6 ^^ y15 x7
        : u64 y10 ^^ y15 t0
        : u64 y11 ^^ y20 y9
        : u64 y7 ^^ x7 y11
        : u64 y17 ^^ y10 y11
        : u64 y19 ^^ y10 y8
        : u64 y16 ^^ t0 y11
        : u64 y21 ^^ y13 y16
        : u64 y18 ^^ x0 y16

        : u64 t2 & y12 y15
        : u64 t3 & y3 y6
        : u64 t4 ^^ t3 t2
        : u64 t5 & y4 x7
        : u64 t6 ^^ t5 t2
        : u64 t7 & y13 y16
        : u64 t8 & y5 y1
        : u64 t9 ^^ t8 t7
        : u64 t10 & y2 y7
        : u64 t11 ^^ t10 t7
        : u64 t12 & y9 y11
        : u64 t13 & y14 y17
        : u64 t14 ^^ t13 t12
        : u64 t15 & y8 y10
        : u64 t16 ^^ t15 t12
        : u64 t17 ^^ t4 t14
        : u64 t18 ^^ t6 t16
        : u64 t19 ^^ t9 t14
        : u64 t20 ^^ t11 t16
        : u64 t21 ^^ t17 y20
        : u64 t22 ^^ t18 y19
        : u64 t23 ^^ t19 y21
        : u64 t24 ^^ t20 y18

        : u64 t25 ^^ t21 t22
        : u64 t26 & t21 t23
        : u64 t27 ^^ t24 t26
        : u64 t28 & t25 t27
        : u64 t29 ^^ t28 t22
        : u64 t30 ^^ t23 t24
        : u64 t31 ^^ t22 t26
        : u64 t32 & t31 t30
        : u64 t33 ^^ t32 t24
        : u64 t34 ^^ t23 t33
        : u64 t35 ^^ t27 t33
        : u64 t36 & t24 t35
        : u64 t37 ^^ t36 t34
        : u64 t38 ^^ t27 t36
        : u64 t39 & t29 t38
        : u64 t40 ^^ t25 t39

        : u64 t41 ^^ t40 t37
        : u64 t42 ^^ t29 t33
        : u64 t43 ^^ t29 t40
        : u64 t44 ^^ t33 t37
        : u64 t45 ^^ t42 t41
        : u64 z0 & t44 y15
        : u64 z1 & t37 y6
        : u64 z2 & t33 x7
        : u64 z3 & t43 y16
        : u64 z4 & t40 y1
        : u64 z5 & t29 y7
        : u64 z6 & t42 y11
        : u64 z7 & t45 y17
        : u64 z8 & t41 y10
        : u64 z9 & t44 y12
        : u64 z10 & t37 y3
        : u64 z11 & t33 y4
        : u64 z12 & t43 y13
        : u64 z13 & t40 y5
        : u64 z14 & t29 y2
        : u64 z15 & t42 y9
        : u64 z16 & t45 y14
        : u64 z17 & t41 y8

        : u64 t46 ^^ z15 z16
        : u64 t47 ^^ z10 z11
        : u64 t48 ^^ z5 z13
        : u64 t49 ^^ z9 z10
        : u64 t50 ^^ z2 z12
        : u64 t51 ^^ z2 z5
        : u64 t52 ^^ z7 z8
        : u64 t53 ^^ z0 z3
        : u64 t54 ^^ z6 z7
        : u64 t55 ^^ z16 z17
        : u64 t56 ^^ z12 t48
        : u64 t57 ^^ t50 t53
        : u64 t58 ^^ z4 t46
        : u64 t59 ^^ z3 t54
        : u64 t60 ^^ t46 t57
        : u64 t61 ^^ z14 t57
        : u64 t62 ^^ t52 t58
        : u64 t63 ^^ t49 t58
        : u64 t64 ^^ z4 t59
        : u64 t65 ^^ t61 t62
        : u64 t66 ^^ z1 t63
        : u64 c0 ^^ t59 t63
        : u64 c6 ^^ ^^ t56 t62 0xFFFFFFFFFFFFFFFF
        : u64 c7 ^^ ^^ t48 t60 0xFFFFFFFFFFFFFFFF
        : u64 t67 ^^ t64 t65
        : u64 c3 ^^ t53 t66
        : u64 c4 ^^ t51 t66
        : u64 c5 ^^ t47 t65
        : u64 c1 ^^ ^^ t64 c3 0xFFFFFFFFFFFFFFFF
        : u64 c2 ^^ ^^ t55 t67 0xFFFFFFFFFFFFFFFF

        // ── ShiftRows, on the transposed layout.
        : u64 s0 | | | | | | & c7 0x000000000000FFFF >> & c7 0x00000000FFF00000 4 << & c7 0x00000000000F0000 12 >> & c7 0x0000FF0000000000 8 << & c7 0x000000FF00000000 8 >> & c7 0xF000000000000000 12 << & c7 0x0FFF000000000000 4
        : u64 s1 | | | | | | & c6 0x000000000000FFFF >> & c6 0x00000000FFF00000 4 << & c6 0x00000000000F0000 12 >> & c6 0x0000FF0000000000 8 << & c6 0x000000FF00000000 8 >> & c6 0xF000000000000000 12 << & c6 0x0FFF000000000000 4
        : u64 s2 | | | | | | & c5 0x000000000000FFFF >> & c5 0x00000000FFF00000 4 << & c5 0x00000000000F0000 12 >> & c5 0x0000FF0000000000 8 << & c5 0x000000FF00000000 8 >> & c5 0xF000000000000000 12 << & c5 0x0FFF000000000000 4
        : u64 s3 | | | | | | & c4 0x000000000000FFFF >> & c4 0x00000000FFF00000 4 << & c4 0x00000000000F0000 12 >> & c4 0x0000FF0000000000 8 << & c4 0x000000FF00000000 8 >> & c4 0xF000000000000000 12 << & c4 0x0FFF000000000000 4
        : u64 s4 | | | | | | & c3 0x000000000000FFFF >> & c3 0x00000000FFF00000 4 << & c3 0x00000000000F0000 12 >> & c3 0x0000FF0000000000 8 << & c3 0x000000FF00000000 8 >> & c3 0xF000000000000000 12 << & c3 0x0FFF000000000000 4
        : u64 s5 | | | | | | & c2 0x000000000000FFFF >> & c2 0x00000000FFF00000 4 << & c2 0x00000000000F0000 12 >> & c2 0x0000FF0000000000 8 << & c2 0x000000FF00000000 8 >> & c2 0xF000000000000000 12 << & c2 0x0FFF000000000000 4
        : u64 s6 | | | | | | & c1 0x000000000000FFFF >> & c1 0x00000000FFF00000 4 << & c1 0x00000000000F0000 12 >> & c1 0x0000FF0000000000 8 << & c1 0x000000FF00000000 8 >> & c1 0xF000000000000000 12 << & c1 0x0FFF000000000000 4
        : u64 s7 | | | | | | & c0 0x000000000000FFFF >> & c0 0x00000000FFF00000 4 << & c0 0x00000000000F0000 12 >> & c0 0x0000FF0000000000 8 << & c0 0x000000FF00000000 8 >> & c0 0xF000000000000000 12 << & c0 0x0FFF000000000000 4

        = q0 s0
        = q1 s1
        = q2 s2
        = q3 s3
        = q4 s4
        = q5 s5
        = q6 s6
        = q7 s7

        // ── MixColumns, every round but the last.
        ? < round nr {
            : u64 r0 | >> q0 16 << q0 48
            : u64 r1 | >> q1 16 << q1 48
            : u64 r2 | >> q2 16 << q2 48
            : u64 r3 | >> q3 16 << q3 48
            : u64 r4 | >> q4 16 << q4 48
            : u64 r5 | >> q5 16 << q5 48
            : u64 r6 | >> q6 16 << q6 48
            : u64 r7 | >> q7 16 << q7 48
            : u64 a0 ^^ q0 r0
            : u64 a1 ^^ q1 r1
            : u64 a2 ^^ q2 r2
            : u64 a3 ^^ q3 r3
            : u64 a4 ^^ q4 r4
            : u64 a5 ^^ q5 r5
            : u64 a6 ^^ q6 r6
            : u64 a7 ^^ q7 r7
            : u64 m0 ^^ ^^ ^^ q7 r7 r0 | << a0 32 >> a0 32
            : u64 m1 ^^ ^^ ^^ ^^ ^^ q0 r0 q7 r7 r1 | << a1 32 >> a1 32
            : u64 m2 ^^ ^^ ^^ q1 r1 r2 | << a2 32 >> a2 32
            : u64 m3 ^^ ^^ ^^ ^^ ^^ q2 r2 q7 r7 r3 | << a3 32 >> a3 32
            : u64 m4 ^^ ^^ ^^ ^^ ^^ q3 r3 q7 r7 r4 | << a4 32 >> a4 32
            : u64 m5 ^^ ^^ ^^ q4 r4 r5 | << a5 32 >> a5 32
            : u64 m6 ^^ ^^ ^^ q5 r5 r6 | << a6 32 >> a6 32
            : u64 m7 ^^ ^^ ^^ q6 r6 r7 | << a7 32 >> a7 32
            = q0 m0
            = q1 m1
            = q2 m2
            = q3 m3
            = q4 m4
            = q5 m5
            = q6 m6
            = q7 m7
        } {}

        // ── AddRoundKey.
        : i sb * round 8
        = q0 ^^ q0 # u64 ( nurl_peek skey + sb 0 )
        = q1 ^^ q1 # u64 ( nurl_peek skey + sb 1 )
        = q2 ^^ q2 # u64 ( nurl_peek skey + sb 2 )
        = q3 ^^ q3 # u64 ( nurl_peek skey + sb 3 )
        = q4 ^^ q4 # u64 ( nurl_peek skey + sb 4 )
        = q5 ^^ q5 # u64 ( nurl_peek skey + sb 5 )
        = q6 ^^ q6 # u64 ( nurl_peek skey + sb 6 )
        = q7 ^^ q7 # u64 ( nurl_peek skey + sb 7 )
        = round + round 1
    }

    ( nurl_poke q 0 # i q0 )
    ( nurl_poke q 1 # i q1 )
    ( nurl_poke q 2 # i q2 )
    ( nurl_poke q 3 # i q3 )
    ( nurl_poke q 4 # i q4 )
    ( nurl_poke q 5 # i q5 )
    ( nurl_poke q 6 # i q6 )
    ( nurl_poke q 7 # i q7 )
    ( __ortho8 q 0 )
    ( __ilv_out outp 0 # u64 ( nurl_peek q 0 ) # u64 ( nurl_peek q 4 ) )
    ( __ilv_out outp 16 # u64 ( nurl_peek q 1 ) # u64 ( nurl_peek q 5 ) )
    ( __ilv_out outp 32 # u64 ( nurl_peek q 2 ) # u64 ( nurl_peek q 6 ) )
    ( __ilv_out outp 48 # u64 ( nurl_peek q 3 ) # u64 ( nurl_peek q 7 ) )
}

// ── GHASH over GF(2^128) ─────────────────────────────────────────
// GCM's field puts bit 0 of byte 0 at the HIGH end of the polynomial, so
// the carry-less product is computed both ways round — once on the words
// and once on their bit-reversal — and the halves recombined. `rev64`
// does that reversal.
@ __rev64 u64 x → u64 {
    : ~ u64 v x
    = v | << & v 0x5555555555555555 1 & >> v 1 0x5555555555555555
    = v | << & v 0x3333333333333333 2 & >> v 2 0x3333333333333333
    = v | << & v 0x0F0F0F0F0F0F0F0F 4 & >> v 4 0x0F0F0F0F0F0F0F0F
    = v | << & v 0x00FF00FF00FF00FF 8 & >> v 8 0x00FF00FF00FF00FF
    = v | << & v 0x0000FFFF0000FFFF 16 & >> v 16 0x0000FFFF0000FFFF
    ^ | << v 32 >> v 32
}

// Carry-less 64x64 → 64 multiply (low half), built from ordinary integer
// multiplies. Each operand is split into four interleaved bit groups, so
// within a product no carry can reach the next kept bit; masking the
// result back to its group drops the garbage. Constant-time wherever the
// hardware multiplier is.
@ __bmul64 u64 x u64 y → u64 {
    : u64 x0 & x 0x1111111111111111
    : u64 x1 & x 0x2222222222222222
    : u64 x2 & x 0x4444444444444444
    : u64 x3 & x 0x8888888888888888
    : u64 y0 & y 0x1111111111111111
    : u64 y1 & y 0x2222222222222222
    : u64 y2 & y 0x4444444444444444
    : u64 y3 & y 0x8888888888888888
    : u64 z0 ^^ ^^ ^^ * x0 y0 * x1 y3 * x2 y2 * x3 y1
    : u64 z1 ^^ ^^ ^^ * x0 y1 * x1 y0 * x2 y3 * x3 y2
    : u64 z2 ^^ ^^ ^^ * x0 y2 * x1 y1 * x2 y0 * x3 y3
    : u64 z3 ^^ ^^ ^^ * x0 y3 * x1 y2 * x2 y1 * x3 y0
    ^ | | | & z0 0x1111111111111111 & z1 0x2222222222222222 & z2 0x4444444444444444 & z3 0x8888888888888888
}

// Big-endian 64-bit load of the 8 bytes at `p + off`, zero-filled past
// `avail` bytes. A GHASH block that runs off the end of the message is
// zero-padded, and a negative `avail` means the whole word is padding.
@ __be64_pad * u p i off i avail → u64 {
    ? >= avail 8 {
        ^ | | | | | | | << # u64 # i . p off 56 << # u64 # i . p + off 1 48 << # u64 # i . p + off 2 40 << # u64 # i . p + off 3 32 << # u64 # i . p + off 4 24 << # u64 # i . p + off 5 16 << # u64 # i . p + off 6 8 # u64 # i . p + off 7
    } {}
    : ~ u64 r 0
    : ~ i k 0
    ~ < k 8 {
        : ~ u64 byte 0
        ? < k avail { = byte # u64 # i . p + off k } {}
        = r | << r 8 byte
        = k + k 1
    }
    ^ r
}

// Absorb `len` bytes at `src` into the GHASH accumulator held in the two
// words of `ystate`. The multiplier `h` is passed pre-decomposed because
// the caller absorbs three separate runs (AAD, ciphertext, lengths) and
// the decomposition is per-key, not per-run.
@ __ghash_blocks s ystate u64 h0 u64 h1 u64 h0r u64 h1r u64 h2 u64 h2r * u src i len → v {
    : ~ u64 y0 # u64 ( nurl_peek ystate 0 )
    : ~ u64 y1 # u64 ( nurl_peek ystate 1 )
    : ~ i off 0
    ~ < off len {
        : i rem - len off
        = y1 ^^ y1 ( __be64_pad src off rem )
        = y0 ^^ y0 ( __be64_pad src + off 8 - rem 8 )

        : u64 y0r ( __rev64 y0 )
        : u64 y1r ( __rev64 y1 )
        : u64 y2 ^^ y0 y1
        : u64 y2r ^^ y0r y1r

        : u64 z0 ( __bmul64 y0 h0 )
        : u64 z1 ( __bmul64 y1 h1 )
        : u64 z2a ( __bmul64 y2 h2 )
        : u64 z0h ( __bmul64 y0r h0r )
        : u64 z1h ( __bmul64 y1r h1r )
        : u64 z2ha ( __bmul64 y2r h2r )
        : u64 z2 ^^ z2a ^^ z0 z1
        : u64 z2h ^^ z2ha ^^ z0h z1h
        : u64 z0hs >> ( __rev64 z0h ) 1
        : u64 z1hs >> ( __rev64 z1h ) 1
        : u64 z2hs >> ( __rev64 z2h ) 1

        : u64 w0 z0
        : u64 w1 ^^ z0hs z2
        : u64 w2 ^^ z1 z2hs
        : u64 w3 z1hs

        : u64 v3 | << w3 1 >> w2 63
        : u64 v2 | << w2 1 >> w1 63
        : u64 v1 | << w1 1 >> w0 63
        : u64 v0 << w0 1

        // Reduce modulo x^128 + x^7 + x^2 + x + 1.
        : u64 v2b ^^ v2 ^^ ^^ ^^ v0 >> v0 1 >> v0 2 >> v0 7
        : u64 v1b ^^ v1 ^^ ^^ << v0 63 << v0 62 << v0 57
        : u64 v3b ^^ v3 ^^ ^^ ^^ v1b >> v1b 1 >> v1b 2 >> v1b 7
        : u64 v2c ^^ v2b ^^ ^^ << v1b 63 << v1b 62 << v1b 57

        = y0 v2c
        = y1 v3b
        = off + off 16
    }
    ( nurl_poke ystate 0 # i y0 )
    ( nurl_poke ystate 1 # i y1 )
}

// Big-endian 64-bit store.
@ __st64be * u p i off u64 w → v {
    : ~ i k 0
    ~ < k 8 { = . p + off k # u # i & >> w * 8 - 7 k 255 = k + k 1 }
}

// ── GCM ──────────────────────────────────────────────────────────

// Write the four CTR blocks for counters `ctr .. ctr+3` into the 64-byte
// buffer `cb`, whose nonce bytes the caller has already filled in. The
// counter is the low 32 bits, big-endian, per GCM's inc32.
@ __ctr_fill * u cb i ctr → v {
    : ~ i b 0
    ~ < b 4 {
        : i o + * b 16 12
        : i c & + ctr b 0xFFFFFFFF
        = . cb o # u & >> c 24 255
        = . cb + o 1 # u & >> c 16 255
        = . cb + o 2 # u & >> c 8 255
        = . cb + o 3 # u & c 255
        = b + b 1
    }
}

// The GCM tag over AAD ‖ ciphertext ‖ lengths, masked with E_K(J0).
// `hp` is the 16-byte hash subkey H, `ekp` the 16-byte E_K(J0); the tag
// is written to the 16 bytes at `out`.
@ __gcm_tag_raw * u hp * u ekp * u aadp i aadlen * u ctp i ctlen * u out → v {
    : u64 h1 ( __be64_pad hp 0 8 )
    : u64 h0 ( __be64_pad hp 8 8 )
    : u64 h0r ( __rev64 h0 )
    : u64 h1r ( __rev64 h1 )
    : u64 h2 ^^ h0 h1
    : u64 h2r ^^ h0r h1r
    : s ystate ( nurl_zalloc 16 )
    ? > aadlen 0 { ( __ghash_blocks ystate h0 h1 h0r h1r h2 h2r aadp aadlen ) } {}
    ? > ctlen 0 { ( __ghash_blocks ystate h0 h1 h0r h1r h2 h2r ctp ctlen ) } {}
    // Length block: [len(AAD)*8]_64 ‖ [len(C)*8]_64.
    : *u lenb # *u ( nurl_zalloc 16 )
    ( __st64be lenb 0 # u64 * aadlen 8 )
    ( __st64be lenb 8 # u64 * ctlen 8 )
    ( __ghash_blocks ystate h0 h1 h0r h1r h2 h2r lenb 16 )
    ( __st64be out 0 # u64 ( nurl_peek ystate 1 ) )
    ( __st64be out 8 # u64 ( nurl_peek ystate 0 ) )
    : ~ i k 0
    ~ < k 16 { = . out k # u ^^ # i . out k # i . ekp k = k + k 1 }
    ( nurl_free # s lenb )
    ( nurl_free ystate )
}

// One CTR pass plus the tag. `input` is the data to transform (plaintext
// when sealing, ciphertext when opening) and the returned Vec is the
// other one; the tag over the CIPHERTEXT — `out` when sealing, `input`
// when opening — is written to the 16 bytes at `tagp`.
//
// The round keys, the hash subkey and the scratch buffers are set up once
// here and reused across every block of the record.
@ __gcm_run ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad * u inp i n i sealing * u tagp → ( Vec u ) {
    : i nr ( __aes_nr key )
    : ( Vec u ) rk ( __aes_expand key )
    : s skey ( __skey_bitslice rk nr )
    ( vec_free [u] rk )
    : s q ( nurl_zalloc 64 )
    : *u cb # *u ( nurl_zalloc 64 )
    : *u kb # *u ( nurl_zalloc 64 )

    // One cipher call covers both fixed blocks: slot 0 is the all-zero
    // block whose ciphertext is the hash subkey H, slot 1 is J0 =
    // nonce ‖ 0x00000001, whose ciphertext masks the tag.
    : ~ i ni 0
    ~ < ni 12 { = . cb + 16 ni # u ( __aes_bget nonce ni ) = ni + ni 1 }
    = . cb 31 # u 1
    ( __aes_ct64_enc4 cb kb skey nr q )
    : *u hj # *u ( nurl_zalloc 32 )
    : ~ i hi 0
    ~ < hi 32 { = . hj hi . kb hi = hi + hi 1 }

    // The counter blocks all carry the same nonce; only the last four
    // bytes change, so the nonce is written once and left alone.
    : ~ i bi 0
    ~ < bi 4 {
        : ~ i nj 0
        ~ < nj 12 { = . cb + * bi 16 nj # u ( __aes_bget nonce nj ) = nj + nj 1 }
        = bi + bi 1
    }

    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    : b _ol ( vec_set_len [u] out n )
    : *u op ( vec_data [u] out )
    : ~ i off 0
    : ~ i ctr 2
    ~ < off n {
        ( __ctr_fill cb ctr )
        ( __aes_ct64_enc4 cb kb skey nr q )
        : i lim ? < - n off 64 - n off 64
        : ~ i j 0
        ~ < j lim {
            = . op + off j # u ^^ # i . inp + off j # i . kb j
            = j + j 1
        }
        = off + off 64
        = ctr + ctr 4
    }

    : *u ctp ? == sealing 1 op inp
    ( __gcm_tag_raw hj # *u + # i hj 16 ( vec_data [u] aad ) ( vec_len [u] aad ) ctp n tagp )

    ( nurl_free # s hj )
    ( nurl_free # s kb )
    ( nurl_free # s cb )
    ( nurl_free q )
    ( nurl_free skey )
    ^ out
}

// AES-GCM seal: ciphertext with the 16-byte tag appended.
@ __gcm_seal ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → ( Vec u ) {
    : i n ( vec_len [u] pt )
    : *u tagp # *u ( nurl_zalloc 16 )
    : ( Vec u ) ct ( __gcm_run key nonce aad ( vec_data [u] pt ) n 1 tagp )
    : ~ i ti 0
    ~ < ti 16 { ( vec_push [u] ct . tagp ti ) = ti + ti 1 }
    ( nurl_free # s tagp )
    ^ ct
}

// AES-GCM open: `ct_tag` is ciphertext followed by its 16-byte tag.
// The tag is verified BEFORE the plaintext is handed back, and the
// comparison is a constant-time OR-accumulate.
@ __gcm_open ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_tag → ?( Vec u ) {
    : i total ( vec_len [u] ct_tag )
    : i ctlen - total 16
    : *u ctp ( vec_data [u] ct_tag )
    : *u tagp # *u ( nurl_zalloc 16 )
    : ( Vec u ) pt ( __gcm_run key nonce aad ctp ctlen 0 tagp )
    : ~ i diff 0
    : ~ i k 0
    ~ < k 16 { = diff | diff ^^ # i . tagp k # i . ctp + ctlen k = k + k 1 }
    ( nurl_free # s tagp )
    ? != diff 0 { ( vec_free [u] pt ) ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    ^ @ ?( Vec u ) { T pt }
}

// AES-128-GCM seal: returns ciphertext with the 16-byte tag appended.
@ aes128_gcm_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → ( Vec u ) {
    // M5/L6: validate key (16 B) / nonce (12 B) and the GCM plaintext cap
    // (2^39−256 bits = 2^36−32 bytes). A wrong nonce length would otherwise
    // silently produce a malformed-but-accepted nonce → catastrophic reuse.
    ? | != ( vec_len [u] key ) 16 != ( vec_len [u] nonce ) 12 { ^ ( vec_new [u] ) } {}
    ? > ( vec_len [u] pt ) 68719476704 { ^ ( vec_new [u] ) } {}
    ^ ( __gcm_seal key nonce aad pt )
}

// AES-128-GCM open. None on tag mismatch.
@ aes128_gcm_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_tag → ?( Vec u ) {
    ? | != ( vec_len [u] key ) 16 != ( vec_len [u] nonce ) 12 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    ? < ( vec_len [u] ct_tag ) 16 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    ^ ( __gcm_open key nonce aad ct_tag )
}

// AES-256-GCM (NIST SP 800-38D) — same GCM construction with a 32-byte key;
// the block cipher core dispatches on key length (14 rounds). This is the
// TLS_AES_256_GCM_SHA384 record protection and the AEAD used by ext/crypto.
@ aes256_gcm_encrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → ( Vec u ) {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ ( vec_new [u] ) } {}
    ? > ( vec_len [u] pt ) 68719476704 { ^ ( vec_new [u] ) } {}
    ^ ( __gcm_seal key nonce aad pt )
}

// AES-256-GCM open. None on tag mismatch.
@ aes256_gcm_decrypt ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_tag → ?( Vec u ) {
    ? | != ( vec_len [u] key ) 32 != ( vec_len [u] nonce ) 12 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    ? < ( vec_len [u] ct_tag ) 16 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    ^ ( __gcm_open key nonce aad ct_tag )
}
