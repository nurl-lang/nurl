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
// Per-key context — prepare the key ONCE (hardware round keys and GHASH
// powers, or the bitsliced software key), then seal/open any
// number of messages under it (a QUIC connection protects a packet of
// ~1200 bytes per call, where the per-call key setup the one-shot API
// pays is a large fraction of the work; TLS records use it too):
//
//   ( aes_gcm_key_new key )                 → AesGcmKey  (16 or 32 B key; a null key —
//                                                         aes_gcm_key_ok F — on a bad length)
//   ( aes_gcm_key_ok k )                    → b
//   ( aes_gcm_seal   k nonce aad pt )       → ( Vec u )  ct||tag
//   ( aes_gcm_open   k nonce aad ct_tag )   → ?( Vec u )
//   ( aes_block_encrypt k block16 )         → ( Vec u )  one raw AES block (header protection)
//   ( aes_gcm_key_free k )                  → v          early release (optional)
//
// In place, the nonce the 12-byte iv with a 64-bit sequence number XORed
// into its tail (TLS 1.3 / QUIC) — a record layer's form, no Vec per
// record:
//
//   ( aes_gcm_seal_in k iv seq buf aad_at data_at )     → b  seal buf[data_at, len), append the tag
//   ( aes_gcm_open_in k iv seq buf aad_at data_at end ) → b  open buf[data_at, end) (ct‖tag) in place
//
// An AesGcmKey is a library handle (docs/MEMORY.md §7.6): every copy is
// the same prepared key, and the last owner releases it.
//
// ── Why this file looks the way it does ───────────────────────────
//
// Constant time is not negotiable here: a table-driven AES indexes memory
// with key-dependent bytes and leaks the key through the cache, which is
// the whole reason CPUs grew AES instructions. Where the CPU has them
// (AES-NI + PCLMULQDQ — `nurl_cpu_has_aes`), a key is built for the
// HARDWARE PATH further down, written on the language's crypto-tier
// primitives: ~3 GB/s, constant-time by construction. Everywhere else
// the constant-time requirement has to be met in software, and the rest
// of this note is about how.
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
$ `stdlib/core/rcbox.nu`

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
// replicated into all four block slots, plus 16 spare bytes at the end
// (`__hsub_at`) for the GHASH subkey. Runs once per key; `q` is the
// caller's 8-word scratch.
@ __hsub_at i nr → i { ^ * 64 + nr 1 }

@ __skey_bitslice ( Vec u ) rk i nr s q → ( Vec u ) {
    : ( Vec u ) skv ( vec_zeroed [u] + ( __hsub_at nr ) 16 )
    : s sk # s ( vec_data [u] skv )
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
    ^ skv
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
// is written to the 16 bytes at `out`. `scr` is 32 bytes of the caller's
// zeroed scratch: the GHASH state, then the length block.
@ __gcm_tag_raw * u hp * u ekp * u aadp i aadlen * u ctp i ctlen * u out s scr → v {
    : u64 h1 ( __be64_pad hp 0 8 )
    : u64 h0 ( __be64_pad hp 8 8 )
    : u64 h0r ( __rev64 h0 )
    : u64 h1r ( __rev64 h1 )
    : u64 h2 ^^ h0 h1
    : u64 h2r ^^ h0r h1r
    : s ystate scr
    ? > aadlen 0 { ( __ghash_blocks ystate h0 h1 h0r h1r h2 h2r aadp aadlen ) } {}
    ? > ctlen 0 { ( __ghash_blocks ystate h0 h1 h0r h1r h2 h2r ctp ctlen ) } {}
    // Length block: [len(AAD)*8]_64 ‖ [len(C)*8]_64.
    : *u lenb # *u + # i scr 16
    ( __st64be lenb 0 # u64 * aadlen 8 )
    ( __st64be lenb 8 # u64 * ctlen 8 )
    ( __ghash_blocks ystate h0 h1 h0r h1r h2 h2r lenb 16 )
    ( __st64be out 0 # u64 ( nurl_peek ystate 1 ) )
    ( __st64be out 8 # u64 ( nurl_peek ystate 0 ) )
    : ~ i k 0
    ~ < k 16 { = . out k # u ^^ # i . out k # i . ekp k = k + k 1 }
}

// ── Hardware path: AES-NI + PCLMULQDQ ────────────────────────────
// Everything above is the software cipher, kept for CPUs without the
// crypto tier (nurl_cpu_has_aes F: pre-2010 x86, an AArch64 core without
// the Cryptographic Extension, RISC-V). Where the CPU has AES-NI and
// PCLMULQDQ — or AES and PMULL on AArch64, which nurlc lowers the same
// primitives to — the same AEAD runs on the language's crypto
// primitives instead — one AES round instruction per round per block,
// three carry-less multiplies per GHASH block — and is constant-time by
// construction: neither instruction has a data-dependent timing.
//
// GHASH in the reflected domain. GCM numbers a block's bits from the
// most significant bit of byte 0 as x^0, so a block byte-reversed
// (nurl_v128_bswap128) and read little-endian is the polynomial
// bit-reversed: bit 127-i holds the coefficient of x^i. Call that X'
// and read it as a polynomial in y. The carry-less product of two such
// values is the reversed product shifted down by one bit, and reduction
// modulo P(x) = x^128 + x^7 + x^2 + x + 1 becomes a MONTGOMERY reduction
// from the low end modulo the reciprocal P*(y) = 1 + y^121 + y^126 +
// y^127 + y^128: for T = A'·G (256 bits, T1·y^128 + T0),
//
//     R' = T·y^-128 mod P*  =  T1 ^ W ^ clmul(W.hi, q),
//     W  = T0 ^ swap64(clmul(T0.lo, q)),   q = 0xC200000000000000
//
// — two carry-less multiplies (q holds y^121 + y^126 + y^127, the
// inverse of P* mod y^128 being 1 + that). The one-bit shift and the
// y^-128 are both folded into the key: G = y·H' mod P* (`__ghw_twist`)
// makes R' exactly the reflected A·H mod P. The derivation is in the
// CHANGELOG entry that introduced this path; the oracle is the software
// GHASH above, against which the tests compare every length.
//
// Eight blocks are folded per reduction: block j of a batch times
// H^(8-j), the 256-bit products summed unreduced (lo, hi and the
// Karatsuba middle kept apart), one reduction at the end. The key
// therefore carries G for H^8 .. H^1 and, beside each, its two halves
// XORed (the Karatsuba middle's multiplicand).
//
// Key layout (the `hkey` of AesGcmKeyImpl): the round keys, 16·(nr+1)
// bytes; then G_8 .. G_1 (128 bytes); then KX_8 .. KX_1 (128 bytes),
// KX's low half being G's halves XORed.

// The running XOR of one key-schedule step: w0 ^= t, then each word
// absorbs the one before it.
@ __ks_chain v128 k i t → v128 {
    : i w0 ^^ # i ( nurl_v128_get32 k 0 ) t
    : i w1 ^^ # i ( nurl_v128_get32 k 1 ) w0
    : i w2 ^^ # i ( nurl_v128_get32 k 2 ) w1
    : i w3 ^^ # i ( nurl_v128_get32 k 3 ) w2
    ^ ( nurl_v128_set32 w0 w1 w2 w3 )
}

// SubWord(x) ^ rcon in lane 0: AESENCLAST on x broadcast to all four
// columns, where ShiftRows is the identity.
@ __ks_subword i x i rcon → i {
    ^ # i ( nurl_v128_get32 ( nurl_v128_aesenclast ( nurl_v128_bcast32 x ) ( nurl_v128_bcast32 rcon ) ) 0 )
}

// xtime on the round constant: 1, 2, 4, …, 0x80, 0x1b, 0x36.
@ __ks_next_rcon i rc → i { ^ & 255 ^^ << rc 1 * 27 >> rc 7 }

// AES-128 key schedule → 11 round keys at `rk`. RotWord on a
// little-endian word is a rotate right by 8.
unsafe inline @ __aes_hw_expand128 * u key * u rk → v {
    : ~ v128 k ( nurl_v128_ld # s key )
    ( nurl_v128_st # s rk k )
    : ~ i rc 1
    : ~ i r 1
    ~ <= r 10 {
        = k ( __ks_chain k ( __ks_subword ( nurl_rotr32 # i ( nurl_v128_get32 k 3 ) 8 ) rc ) )
        ( nurl_v128_st # s + # i rk * r 16 k )
        = rc ( __ks_next_rcon rc )
        = r + r 1
    }
}

// AES-256 key schedule → 15 round keys at `rk`: alternating steps, the
// odd ones SubWord without RotWord or a round constant.
unsafe inline @ __aes_hw_expand256 * u key * u rk → v {
    : ~ v128 ka ( nurl_v128_ld # s key )
    : ~ v128 kb ( nurl_v128_ld # s + # i key 16 )
    ( nurl_v128_st # s rk ka )
    ( nurl_v128_st # s + # i rk 16 kb )
    : ~ i rc 1
    : ~ i r 1
    ~ <= r 7 {
        = ka ( __ks_chain ka ( __ks_subword ( nurl_rotr32 # i ( nurl_v128_get32 kb 3 ) 8 ) rc ) )
        ( nurl_v128_st # s + # i rk * * r 2 16 ka )
        ? < r 7 {
            = kb ( __ks_chain kb ( __ks_subword # i ( nurl_v128_get32 ka 3 ) 0 ) )
            ( nurl_v128_st # s + # i rk * + * r 2 1 16 kb )
        } {}
        = rc ( __ks_next_rcon rc )
        = r + r 1
    }
}

// One block through the cipher.
unsafe @ __aes_hw_enc1 * u rk i nr v128 x → v128 {
    : ~ v128 b ( nurl_v128_xor x ( nurl_v128_ld # s rk ) )
    : ~ i r 1
    ~ < r nr { = b ( nurl_v128_aesenc b ( nurl_v128_ld # s + # i rk * r 16 ) ) = r + r 1 }
    ^ ( nurl_v128_aesenclast b ( nurl_v128_ld # s + # i rk * nr 16 ) )
}

// The 256-bit lo / hi / Karatsuba-middle triple, recombined into
// T1·y^128 + T0 and Montgomery-reduced (see above). One function, not a
// recombine calling a reduce: a helper is compiled for the crypto tier
// only when it uses a crypto primitive itself, and only a tier helper
// inlines into the kernel without a gate of its own.
@ __ghw_finish v128 lo v128 hi v128 md0 → v128 {
    : v128 z ( nurl_v128_zero )
    : v128 md ( nurl_v128_xor md0 ( nurl_v128_xor lo hi ) )
    : v128 t0 ( nurl_v128_xor lo ( nurl_v128_unpacklo64 z md ) )
    : v128 t1 ( nurl_v128_xor hi ( nurl_v128_unpackhi64 md z ) )
    : v128 q ( nurl_v128_set64 0xC200000000000000 0 )
    : v128 w ( nurl_v128_xor t0 ( nurl_v128_rotlanes2 ( nurl_v128_clmul_ll t0 q ) ) )
    ^ ( nurl_v128_xor ( nurl_v128_xor t1 w ) ( nurl_v128_clmul_hl w q ) )
}

// One GHASH multiply, a·H for the twisted key g = G_1.
@ __ghw_mul v128 a v128 g → v128 {
    : v128 lo ( nurl_v128_clmul_ll a g )
    : v128 hi ( nurl_v128_clmul_hh a g )
    : v128 md ( nurl_v128_clmul_ll ( nurl_v128_xor a ( nurl_v128_rotlanes2 a ) ) ( nurl_v128_xor g ( nurl_v128_rotlanes2 g ) ) )
    ^ ( __ghw_finish lo hi md )
}

// G = y·H' mod P*: a one-bit left shift of the 128-bit value, and the
// reduction 1 + y^121 + y^126 + y^127 when a bit falls off the top —
// selected with a mask, not a branch.
@ __ghw_twist v128 h → v128 {
    : u64 lo ( nurl_v128_get64 h 0 )
    : u64 hi ( nurl_v128_get64 h 1 )
    : u64 m - # u64 0 >> hi 63
    : u64 nlo ^^ << lo 1 & m 1
    : u64 nhi ^^ | << hi 1 >> lo 63 & m 0xC200000000000000
    ^ ( nurl_v128_set64 # i nlo # i nhi )
}

// The whole key state at `hk` (layout above) from a 16- or 32-byte key.
// `simd`, so the schedule and GHASH helpers inline into its clones.
unsafe simd @ __gcm_hw_init * u key i klen * u hk → v {
    : i nr ? == klen 32 14 10
    ? == klen 32 { ( __aes_hw_expand256 key hk ) } { ( __aes_hw_expand128 key hk ) }
    // H = E_K(0^128), reflected.
    : v128 h ( nurl_v128_bswap128 ( __aes_hw_enc1 hk nr ( nurl_v128_zero ) ) )
    : v128 g1 ( __ghw_twist h )
    : *u gt # *u + # i hk * 16 + nr 1
    : ~ v128 hp h
    : ~ i k 1
    ~ <= k 8 {
        : v128 g ( __ghw_twist hp )
        : i slot * 16 - 8 k
        ( nurl_v128_st # s + # i gt slot g )
        ( nurl_v128_st # s + # i gt + 128 slot ( nurl_v128_xor g ( nurl_v128_rotlanes2 g ) ) )
        // H'^(k+1) = H'^k · H, reflected
        = hp ( __ghw_mul hp g1 )
        = k + k 1
    }
}

// The low `m` bytes (1..15) of a block set, the rest clear: what keeps
// the keystream past a short last block out of its GHASH input.
@ __lowmask i m → v128 {
    : u64 one 1
    : u64 lo ? >= m 8 # u64 -1 - << one # u64 * m 8 one
    : u64 hi ? > m 8 - << one # u64 * - m 8 8 one # u64 0
    ^ ( nurl_v128_set64 # i lo # i hi )
}

// Eight ciphertext blocks at `c` folded into `acc` with one reduction:
// block j times H^(8-j) (G and KX tables at `gt`), lo / hi / middle
// summed unreduced.
unsafe @ __ghw_fold8 v128 acc * u c * u gt → v128 {
    : v128 x0 ( nurl_v128_xor acc ( nurl_v128_bswap128 ( nurl_v128_ld # s c ) ) )
    : v128 g0 ( nurl_v128_ld # s gt )
    : ~ v128 lo ( nurl_v128_clmul_ll x0 g0 )
    : ~ v128 hi ( nurl_v128_clmul_hh x0 g0 )
    : ~ v128 md ( nurl_v128_clmul_ll ( nurl_v128_xor x0 ( nurl_v128_rotlanes2 x0 ) ) ( nurl_v128_ld # s + # i gt 128 ) )
    : ~ i j 1
    ~ < j 8 {
        : v128 x ( nurl_v128_bswap128 ( nurl_v128_ld # s + # i c * j 16 ) )
        : v128 g ( nurl_v128_ld # s + # i gt * j 16 )
        = lo ( nurl_v128_xor lo ( nurl_v128_clmul_ll x g ) )
        = hi ( nurl_v128_xor hi ( nurl_v128_clmul_hh x g ) )
        = md ( nurl_v128_xor md ( nurl_v128_clmul_ll ( nurl_v128_xor x ( nurl_v128_rotlanes2 x ) ) ( nurl_v128_ld # s + # i gt + 128 * j 16 ) ) )
        = j + j 1
    }
    ^ ( __ghw_finish lo hi md )
}

// The counter block for counter `c`: the nonce words, then c big-endian.
@ __ctr_blk i n0 i n1 i n2 i c → v128 { ^ ( nurl_v128_set32 n0 n1 n2 ( nurl_bswap32 c ) ) }

// Counter block c+j from block c's `cb` by a byte add on the counter's
// low byte (the block's last) — valid while that byte does not carry,
// which the caller checks. A vector add instead of a scalar byte swap
// and an insert per block: the insert competes for the shuffle port
// that AESENC and PCLMULQDQ already saturate.
@ __ctr_add v128 cb i j → v128 { ^ ( nurl_v128_add8 cb ( nurl_v128_set32 0 0 0 << j 24 ) ) }

// One GHASH block of an eight-block fold: x (already byte-swapped and,
// for block 0, XORed with the accumulator) times the table entry j,
// added to the unreduced lo / hi / middle sums.
@ __ghw_acc1 v128 x * u gt i j inout v128 lo inout v128 hi inout v128 md → v {
    : v128 g ( nurl_v128_ld # s + # i gt * j 16 )
    = lo ( nurl_v128_xor lo ( nurl_v128_clmul_ll x g ) )
    = hi ( nurl_v128_xor hi ( nurl_v128_clmul_hh x g ) )
    = md ( nurl_v128_xor md ( nurl_v128_clmul_ll ( nurl_v128_xor x ( nurl_v128_rotlanes2 x ) ) ( nurl_v128_ld # s + # i gt + 128 * j 16 ) ) )
}

// One block of a GHASH run that reduces once per group of up to eight
// blocks instead of once per block: `x` (byte-swapped) times H^p,
// summed unreduced into lo / hi / md, with the reduced accumulator XORed
// into the group's first block and then cleared, so the group's later
// blocks do not see it again. The block that brings `p` to 0 closes the
// group — one reduction into `acc` — and opens the next one at
// min(8, rem) blocks. `rem` counts the run's blocks still to come, this
// one included, so the run's last block always closes a group.
//
// A run of AAD, a short message and the length block — at most eight
// blocks for a TLS record of up to 96 bytes — is therefore ONE
// multiply-sum and one reduction, where a block at a time chained a
// reduction per block, each waiting on the one before.
@ __ghw_take v128 x * u gt inout v128 acc inout v128 lo inout v128 hi inout v128 md inout i p inout i rem → v {
    ( __ghw_acc1 ( nurl_v128_xor x acc ) gt - 8 p lo hi md )
    = acc ( nurl_v128_zero )
    = p - p 1
    = rem - rem 1
    ? == p 0 {
        = acc ( __ghw_finish lo hi md )
        = lo ( nurl_v128_zero )
        = hi ( nurl_v128_zero )
        = md ( nurl_v128_zero )
        = p ? > rem 8 8 rem
    } {}
}

// One AES round on eight blocks.
@ __aes_round8 v128 k inout v128 b0 inout v128 b1 inout v128 b2 inout v128 b3 inout v128 b4 inout v128 b5 inout v128 b6 inout v128 b7 → v {
    = b0 ( nurl_v128_aesenc b0 k )
    = b1 ( nurl_v128_aesenc b1 k )
    = b2 ( nurl_v128_aesenc b2 k )
    = b3 ( nurl_v128_aesenc b3 k )
    = b4 ( nurl_v128_aesenc b4 k )
    = b5 ( nurl_v128_aesenc b5 k )
    = b6 ( nurl_v128_aesenc b6 k )
    = b7 ( nurl_v128_aesenc b7 k )
}

// Two / four / eight blocks through the whole cipher together, in registers:
// the blocks are independent, so their rounds overlap and the pass
// costs about one block's latency (AESENC is a 4- to 7-cycle latency
// at a throughput of one or two per cycle). Four when that is enough —
// eight blocks of a 10-round cipher are 80 AESENCs, which on a
// one-per-cycle core outlast the latency four of them hide behind.
unsafe @ __aes_hw_enc2 * u rk i nr inout v128 b0 inout v128 b1 → v {
    : v128 k0 ( nurl_v128_ld # s rk )
    = b0 ( nurl_v128_xor b0 k0 )
    = b1 ( nurl_v128_xor b1 k0 )
    : ~ i r 1
    ~ < r nr {
        : v128 k ( nurl_v128_ld # s + # i rk * r 16 )
        = b0 ( nurl_v128_aesenc b0 k )
        = b1 ( nurl_v128_aesenc b1 k )
        = r + r 1
    }
    : v128 kl ( nurl_v128_ld # s + # i rk * nr 16 )
    = b0 ( nurl_v128_aesenclast b0 kl )
    = b1 ( nurl_v128_aesenclast b1 kl )
}

unsafe @ __aes_hw_enc4 * u rk i nr inout v128 b0 inout v128 b1 inout v128 b2 inout v128 b3 → v {
    : v128 k0 ( nurl_v128_ld # s rk )
    = b0 ( nurl_v128_xor b0 k0 )
    = b1 ( nurl_v128_xor b1 k0 )
    = b2 ( nurl_v128_xor b2 k0 )
    = b3 ( nurl_v128_xor b3 k0 )
    : ~ i r 1
    ~ < r nr {
        : v128 k ( nurl_v128_ld # s + # i rk * r 16 )
        = b0 ( nurl_v128_aesenc b0 k )
        = b1 ( nurl_v128_aesenc b1 k )
        = b2 ( nurl_v128_aesenc b2 k )
        = b3 ( nurl_v128_aesenc b3 k )
        = r + r 1
    }
    : v128 kl ( nurl_v128_ld # s + # i rk * nr 16 )
    = b0 ( nurl_v128_aesenclast b0 kl )
    = b1 ( nurl_v128_aesenclast b1 kl )
    = b2 ( nurl_v128_aesenclast b2 kl )
    = b3 ( nurl_v128_aesenclast b3 kl )
}

unsafe @ __aes_hw_enc8 * u rk i nr inout v128 b0 inout v128 b1 inout v128 b2 inout v128 b3 inout v128 b4 inout v128 b5 inout v128 b6 inout v128 b7 → v {
    : v128 k0 ( nurl_v128_ld # s rk )
    = b0 ( nurl_v128_xor b0 k0 )
    = b1 ( nurl_v128_xor b1 k0 )
    = b2 ( nurl_v128_xor b2 k0 )
    = b3 ( nurl_v128_xor b3 k0 )
    = b4 ( nurl_v128_xor b4 k0 )
    = b5 ( nurl_v128_xor b5 k0 )
    = b6 ( nurl_v128_xor b6 k0 )
    = b7 ( nurl_v128_xor b7 k0 )
    : ~ i r 1
    ~ < r nr {
        ( __aes_round8 ( nurl_v128_ld # s + # i rk * r 16 ) b0 b1 b2 b3 b4 b5 b6 b7 )
        = r + r 1
    }
    : v128 kl ( nurl_v128_ld # s + # i rk * nr 16 )
    = b0 ( nurl_v128_aesenclast b0 kl )
    = b1 ( nurl_v128_aesenclast b1 kl )
    = b2 ( nurl_v128_aesenclast b2 kl )
    = b3 ( nurl_v128_aesenclast b3 kl )
    = b4 ( nurl_v128_aesenclast b4 kl )
    = b5 ( nurl_v128_aesenclast b5 kl )
    = b6 ( nurl_v128_aesenclast b6 kl )
    = b7 ( nurl_v128_aesenclast b7 kl )
}

// The stitched loop body: eight CTR blocks (counters ctr .. ctr+7, from
// `inp` into `op`) AND the GHASH fold of the eight ciphertext blocks at
// `prev` into `acc`, the two interleaved round by round. Each round of
// the cipher carries one block of the fold, so the multiplier works
// while the AES unit does, instead of the fold waiting behind a cipher
// whose output it needs. Sealing, `prev` is the batch BEFORE — already
// in memory — and 0 for the first batch, when `acc` comes back
// unchanged. Opening, `prev` is this batch's own input: the ciphertext
// is there before the cipher runs, and every load of it precedes the
// stores, so `op` may be `inp` (an in-place open).
unsafe @ __gcm_hw_stitch8 * u rk i nr i n0 i n1 i n2 i ctr * u inp * u op v128 acc * u prev * u gt → v128 {
    : v128 k0 ( nurl_v128_ld # s rk )
    : v128 cb ( __ctr_blk n0 n1 n2 ctr )
    : ~ v128 b0 cb
    : ~ v128 b1 cb
    : ~ v128 b2 cb
    : ~ v128 b3 cb
    : ~ v128 b4 cb
    : ~ v128 b5 cb
    : ~ v128 b6 cb
    : ~ v128 b7 cb
    ? <= & ctr 255 248 {
        = b1 ( __ctr_add cb 1 )
        = b2 ( __ctr_add cb 2 )
        = b3 ( __ctr_add cb 3 )
        = b4 ( __ctr_add cb 4 )
        = b5 ( __ctr_add cb 5 )
        = b6 ( __ctr_add cb 6 )
        = b7 ( __ctr_add cb 7 )
    } {
        = b1 ( __ctr_blk n0 n1 n2 + ctr 1 )
        = b2 ( __ctr_blk n0 n1 n2 + ctr 2 )
        = b3 ( __ctr_blk n0 n1 n2 + ctr 3 )
        = b4 ( __ctr_blk n0 n1 n2 + ctr 4 )
        = b5 ( __ctr_blk n0 n1 n2 + ctr 5 )
        = b6 ( __ctr_blk n0 n1 n2 + ctr 6 )
        = b7 ( __ctr_blk n0 n1 n2 + ctr 7 )
    }
    = b0 ( nurl_v128_xor b0 k0 )
    = b1 ( nurl_v128_xor b1 k0 )
    = b2 ( nurl_v128_xor b2 k0 )
    = b3 ( nurl_v128_xor b3 k0 )
    = b4 ( nurl_v128_xor b4 k0 )
    = b5 ( nurl_v128_xor b5 k0 )
    = b6 ( nurl_v128_xor b6 k0 )
    = b7 ( nurl_v128_xor b7 k0 )
    : b fold != 0 # i prev
    : v128 z ( nurl_v128_zero )
    : ~ v128 lo z
    : ~ v128 hi z
    : ~ v128 md z
    : ~ i r 1
    ~ < r 9 {
        ( __aes_round8 ( nurl_v128_ld # s + # i rk * r 16 ) b0 b1 b2 b3 b4 b5 b6 b7 )
        // Rounds 1..7 fold blocks 1..7; block 0, the one that carries the
        // accumulator, goes last (round 8), so the step before's
        // reduction has seven rounds to finish before it is needed.
        ? fold {
            : i j ? == r 8 0 r
            : v128 x0 ( nurl_v128_bswap128 ( nurl_v128_ld # s + # i prev * j 16 ) )
            : v128 x ? == j 0 ( nurl_v128_xor x0 acc ) x0
            ( __ghw_acc1 x gt j lo hi md )
        } {}
        = r + r 1
    }
    // Round 9, then 10..13 for a 256-bit key: spelled out, not a loop
    // to `nr`, since nr is only ever 10 or 14 — a loop to a run-time
    // bound costs a trip-count dance for what is one round or four.
    ( __aes_round8 ( nurl_v128_ld # s + # i rk 144 ) b0 b1 b2 b3 b4 b5 b6 b7 )
    ? == nr 14 {
        ( __aes_round8 ( nurl_v128_ld # s + # i rk 160 ) b0 b1 b2 b3 b4 b5 b6 b7 )
        ( __aes_round8 ( nurl_v128_ld # s + # i rk 176 ) b0 b1 b2 b3 b4 b5 b6 b7 )
        ( __aes_round8 ( nurl_v128_ld # s + # i rk 192 ) b0 b1 b2 b3 b4 b5 b6 b7 )
        ( __aes_round8 ( nurl_v128_ld # s + # i rk 208 ) b0 b1 b2 b3 b4 b5 b6 b7 )
    } {}
    : v128 kl ( nurl_v128_ld # s + # i rk * nr 16 )
    ( nurl_v128_st # s op ( nurl_v128_xor ( nurl_v128_aesenclast b0 kl ) ( nurl_v128_ld # s inp ) ) )
    ( nurl_v128_st # s + # i op 16 ( nurl_v128_xor ( nurl_v128_aesenclast b1 kl ) ( nurl_v128_ld # s + # i inp 16 ) ) )
    ( nurl_v128_st # s + # i op 32 ( nurl_v128_xor ( nurl_v128_aesenclast b2 kl ) ( nurl_v128_ld # s + # i inp 32 ) ) )
    ( nurl_v128_st # s + # i op 48 ( nurl_v128_xor ( nurl_v128_aesenclast b3 kl ) ( nurl_v128_ld # s + # i inp 48 ) ) )
    ( nurl_v128_st # s + # i op 64 ( nurl_v128_xor ( nurl_v128_aesenclast b4 kl ) ( nurl_v128_ld # s + # i inp 64 ) ) )
    ( nurl_v128_st # s + # i op 80 ( nurl_v128_xor ( nurl_v128_aesenclast b5 kl ) ( nurl_v128_ld # s + # i inp 80 ) ) )
    ( nurl_v128_st # s + # i op 96 ( nurl_v128_xor ( nurl_v128_aesenclast b6 kl ) ( nurl_v128_ld # s + # i inp 96 ) ) )
    ( nurl_v128_st # s + # i op 112 ( nurl_v128_xor ( nurl_v128_aesenclast b7 kl ) ( nurl_v128_ld # s + # i inp 112 ) ) )
    ? fold { ^ ( __ghw_finish lo hi md ) } {}
    ^ acc
}

// One AES-GCM pass on the hardware path: CTR over `n` bytes from `inp`
// to `op`, and the tag over the ciphertext — `op` when sealing, `inp`
// when opening — written to the 16 bytes at `tagp`. `op` may be `inp`:
// every block's ciphertext is read before its plaintext is written, so
// a record can be sealed or opened where it lies. `ks` is 128 bytes of
// scratch for the tail's keystream. Marked
// `simd`: on an AVX2 machine the VEX-encoded clone runs, whose
// three-operand AESENC / PCLMULQDQ need no register copies.
//
// The message is eight-block steps (the stitched loop) and a tail of 0
// to 8 blocks. The tail's counter blocks go through the cipher in one
// pass together with J0's — whose encryption masks the tag — so a short
// message pays about one block's cipher latency, not one per block.
// GHASH runs reduce once per eight blocks (__ghw_take): the AAD, and
// either the tail and the length block after the steps or, with no
// step, all three in one run — one reduction for a record up to 96
// bytes behind a 5-byte TLS header.
unsafe simd @ __gcm_hw_run * u hk i nr * u nonce * u aadp i aadlen * u inp i n * u op i sealing * u tagp * u ks → v {
    : *u gt # *u + # i hk * 16 + nr 1
    : i n0 # i ( __ld32le nonce 0 )
    : i n1 # i ( __ld32le nonce 4 )
    : i n2 # i ( __ld32le nonce 8 )
    : i o8 & n -128
    : i tctr + 2 / o8 16
    : i tb / + - n o8 15 16
    : v128 z ( nurl_v128_zero )

    // The first GHASH run: the AAD — and with no eight-block step the
    // tail and the length block too.
    : ~ v128 acc z
    : ~ v128 lo z
    : ~ v128 hi z
    : ~ v128 md z
    : ~ i rem ? == o8 0 + + / + aadlen 15 16 tb 1 / + aadlen 15 16
    : ~ i p ? > rem 8 8 rem
    : ~ i off 0
    ~ < off aadlen {
        : v128 x ( nurl_v128_ldn # s + # i aadp off - aadlen off )
        ( __ghw_take ( nurl_v128_bswap128 x ) gt acc lo hi md p rem )
        = off + off 16
    }

    // Eight blocks a step. Sealing, each step folds the step before's
    // ciphertext while it encrypts its own, and the last step's fold is
    // left over after the loop; opening, each folds its own input. The
    // AAD run has closed — `acc` reduced, the sums zero — and the sums
    // are restarted after the loop rather than carried through it: the
    // loop holds eight blocks, a key and three sums of its own in
    // sixteen registers, with nothing to spare.
    = off 0
    ? > o8 0 {
        : ~ i ctr 2
        ~ < off o8 {
            : *u prev ? == sealing 1 ? > off 0 # *u + # i op - off 128 # *u 0 # *u + # i inp off
            = acc ( __gcm_hw_stitch8 hk nr n0 n1 n2 ctr # *u + # i inp off # *u + # i op off acc prev gt )
            = off + off 128
            = ctr + ctr 8
        }
        ? == sealing 1 { = acc ( __ghw_fold8 acc # *u + # i op - o8 128 gt ) } {}
        = lo z
        = hi z
        = md z
        = rem + tb 1
        = p ? > rem 8 8 rem
    } {}

    // E_K(J0), J0 = nonce ‖ 1, and the tail's keystream to `ks` in the
    // narrowest pass that holds both — J0 alone, two, four or eight
    // blocks; a full eight-block tail leaves J0 a pass of its own. Never
    // wider: a block the tail does not use still occupies the AES unit,
    // which the eight-block steps keep saturated.
    : ~ v128 ej0 ( __ctr_blk n0 n1 n2 1 )
    : ~ v128 c0 ( __ctr_blk n0 n1 n2 tctr )
    ? < tb 2 {
        ? == tb 0 { = ej0 ( __aes_hw_enc1 hk nr ej0 ) } {
            ( __aes_hw_enc2 hk nr ej0 c0 )
            ( nurl_v128_st # s ks c0 )
        }
    } {
        : ~ v128 c1 ( __ctr_blk n0 n1 n2 + tctr 1 )
        : ~ v128 c2 ( __ctr_blk n0 n1 n2 + tctr 2 )
        ? < tb 4 {
            ( __aes_hw_enc4 hk nr ej0 c0 c1 c2 )
            ( nurl_v128_st # s ks c0 )
            ( nurl_v128_st # s + # i ks 16 c1 )
            ( nurl_v128_st # s + # i ks 32 c2 )
        } {
            : ~ v128 c3 ( __ctr_blk n0 n1 n2 + tctr 3 )
            : ~ v128 c4 ( __ctr_blk n0 n1 n2 + tctr 4 )
            : ~ v128 c5 ( __ctr_blk n0 n1 n2 + tctr 5 )
            : ~ v128 c6 ( __ctr_blk n0 n1 n2 + tctr 6 )
            ? < tb 8 {
                ( __aes_hw_enc8 hk nr ej0 c0 c1 c2 c3 c4 c5 c6 )
            } {
                : ~ v128 c7 ( __ctr_blk n0 n1 n2 + tctr 7 )
                ( __aes_hw_enc8 hk nr c0 c1 c2 c3 c4 c5 c6 c7 )
                ( nurl_v128_st # s + # i ks 112 c7 )
                = ej0 ( __aes_hw_enc1 hk nr ej0 )
            }
            ( nurl_v128_st # s ks c0 )
            ( nurl_v128_st # s + # i ks 16 c1 )
            ( nurl_v128_st # s + # i ks 32 c2 )
            ( nurl_v128_st # s + # i ks 48 c3 )
            ( nurl_v128_st # s + # i ks 64 c4 )
            ( nurl_v128_st # s + # i ks 80 c5 )
            ( nurl_v128_st # s + # i ks 96 c6 )
        }
    }

    // The tail, a block at a time against `ks`; a short last block's
    // GHASH input is the ciphertext's bytes only, the keystream past
    // them masked off.
    : ~ i j 0
    ~ < off n {
        : v128 k ( nurl_v128_ld # s + # i ks * j 16 )
        : i m - n off
        ? >= m 16 {
            : v128 v ( nurl_v128_ld # s + # i inp off )
            : v128 y ( nurl_v128_xor v k )
            : v128 c ? == sealing 1 y v
            ( __ghw_take ( nurl_v128_bswap128 c ) gt acc lo hi md p rem )
            ( nurl_v128_st # s + # i op off y )
        } {
            : v128 v ( nurl_v128_ldn # s + # i inp off m )
            : v128 y ( nurl_v128_xor v k )
            : v128 c ? == sealing 1 ( nurl_v128_and y ( __lowmask m ) ) v
            ( __ghw_take ( nurl_v128_bswap128 c ) gt acc lo hi md p rem )
            ( nurl_v128_stn # s + # i op off m y )
        }
        = off + off 16
        = j + j 1
    }
    // The length block [len(AAD)·8]_64 ‖ [len(C)·8]_64, reflected: the two
    // bit lengths as little-endian halves, C's in the low one. It closes
    // the last run, so `acc` is reduced after it.
    ( __ghw_take ( nurl_v128_set64 * n 8 * aadlen 8 ) gt acc lo hi md p rem )
    ( nurl_v128_st # s tagp ( nurl_v128_xor ( nurl_v128_bswap128 acc ) ej0 ) )
}

// One raw AES block on the hardware path (aes_block_encrypt).
unsafe @ __aes_hw_block * u hk i nr * u inb * u outb → v {
    ( nurl_v128_st # s outb ( __aes_hw_enc1 hk nr ( nurl_v128_ld # s inb ) ) )
}

// ── Wide hardware path: VAES + VPCLMULQDQ ────────────────────────
// Where the CPU also has the VAES tier (nurl_cpu_has_vaes: Ice Lake and
// later Intel, Zen 3 and later AMD) a message of at least one sixteen-
// block batch runs here instead: the same AEAD, the same reflected
// GHASH and the same Montgomery reduction as the eight-block kernel
// above, on v256 — every AESENC and PCLMULQDQ does two blocks, one per
// 128-bit lane. Sixteen blocks a step, eight ymm registers in flight:
// one VAESENC every half cycle needs eight independent ones to cover
// its latency, and two blocks a register is what makes eight registers
// sixteen blocks. As above, each step folds the step before's ciphertext
// into GHASH while it encrypts its own, one pair of blocks per round.
//
// Shorter messages, and the short records TLS sends most, keep the
// eight-block kernel (__gcm_run_hw decides); the wide one's tail — fewer
// than sixteen blocks after the last full step — is folded with one
// reduction, block j of m times H^(m-j).
//
// GHASH multiplies schoolbook here — four products a block, the middle
// one the sum of the two cross products — where the narrow kernel uses
// Karatsuba's three: the third Karatsuba product needs a lane shuffle
// and an XOR per block on the vector ports AES runs on, and a fourth
// VPCLMULQDQ on its own port is the cheaper of the two (measured ~5% on
// the bulk loop, Sapphire Rapids).
//
// Key layout: the wide state follows the narrow one in `hkey`, at
// __gcm_vaes_at nr: each round key twice over (32·(nr+1) bytes, a ymm
// operand as it stands), then the GHASH powers G_16 .. G_1 and three
// zero entries (19·16 bytes) — so a 32-byte load at entry k is the pair
// (H^(16-k), H^(15-k)) for a block pair whose first block wants
// H^(16-k), and a 64-byte load the four powers of a zmm quadruple.

// Where the wide state starts, and how long it is.
@ __gcm_vaes_at i nr → i { ^ + * 16 + nr 1 256 }

@ __gcm_vaes_len i nr → i { ^ + * 32 + nr 1 304 }

// The wide state for the key whose narrow state __gcm_hw_init already
// wrote at `hk`. `simd`, so the AES-tier helpers inline into its clones.
unsafe simd @ __gcm_vaes_init * u hk i nr → v {
    : *u w # *u + # i hk ( __gcm_vaes_at nr )
    : ~ i r 0
    ~ <= r nr {
        : v128 k ( nurl_v128_ld # s + # i hk * r 16 )
        ( nurl_v128_st # s + # i w * r 32 k )
        ( nurl_v128_st # s + # i w + * r 32 16 k )
        = r + r 1
    }
    : *u gp # *u + # i w * 32 + nr 1
    : v128 h ( nurl_v128_bswap128 ( __aes_hw_enc1 hk nr ( nurl_v128_zero ) ) )
    : v128 g1 ( __ghw_twist h )
    : ~ v128 hp h
    : ~ i k 1
    ~ <= k 16 {
        : v128 g ( __ghw_twist hp )
        : i slot * 16 - 16 k
        ( nurl_v128_st # s + # i gp slot g )
        = hp ( __ghw_mul hp g1 )
        = k + k 1
    }
}

// One AES round on sixteen blocks, two per register.
@ __aes_round16 v256 k inout v256 b0 inout v256 b1 inout v256 b2 inout v256 b3 inout v256 b4 inout v256 b5 inout v256 b6 inout v256 b7 → v {
    = b0 ( nurl_v256_aesenc b0 k )
    = b1 ( nurl_v256_aesenc b1 k )
    = b2 ( nurl_v256_aesenc b2 k )
    = b3 ( nurl_v256_aesenc b3 k )
    = b4 ( nurl_v256_aesenc b4 k )
    = b5 ( nurl_v256_aesenc b5 k )
    = b6 ( nurl_v256_aesenc b6 k )
    = b7 ( nurl_v256_aesenc b7 k )
}

// One block pair of a fold: x (byte-swapped; for the first pair, the
// accumulator already in its low lane) times the power pair at `g`,
// added to the unreduced lo / hi / middle.
unsafe @ __ghw2_acc v256 x * u g inout v256 lo inout v256 hi inout v256 md → v {
    : v256 gv ( nurl_v256_ld # s g )
    = lo ( nurl_v256_xor lo ( nurl_v256_clmul_ll x gv ) )
    = hi ( nurl_v256_xor hi ( nurl_v256_clmul_hh x gv ) )
    = md ( nurl_v256_xor md ( nurl_v256_xor ( nurl_v256_clmul_lh x gv ) ( nurl_v256_clmul_hl x gv ) ) )
}

// The two lanes' sums added together and reduced: the lanes hold
// blocks of one sum, so it is a sum of the halves, then — the middle
// being the true one here, not Karatsuba's — __ghw_finish's
// recombination and reduction — spelled out here, since a helper is
// compiled for a tier only when it uses a primitive itself, and only a
// tier helper inlines into the kernel without a gate of its own (see
// __ghw_finish).
@ __ghw2_finish v256 lo2 v256 hi2 v256 md2 → v128 {
    : v128 lo ( nurl_v128_xor ( nurl_v256_lo128 lo2 ) ( nurl_v256_hi128 lo2 ) )
    : v128 hi ( nurl_v128_xor ( nurl_v256_lo128 hi2 ) ( nurl_v256_hi128 hi2 ) )
    : v128 md ( nurl_v128_xor ( nurl_v256_lo128 md2 ) ( nurl_v256_hi128 md2 ) )
    : v128 z ( nurl_v128_zero )
    : v128 t0 ( nurl_v128_xor lo ( nurl_v128_unpacklo64 z md ) )
    : v128 t1 ( nurl_v128_xor hi ( nurl_v128_unpackhi64 md z ) )
    : v128 q ( nurl_v128_set64 0xC200000000000000 0 )
    : v128 w ( nurl_v128_xor t0 ( nurl_v128_rotlanes2 ( nurl_v128_clmul_ll t0 q ) ) )
    ^ ( nurl_v128_xor ( nurl_v128_xor t1 w ) ( nurl_v128_clmul_hl w q ) )
}

// Counter pair (c+j, c+j+1) from pair (c, c+1)'s `cb` by a byte add on
// both counters' low bytes — valid while they do not carry, which the
// caller checks (__ctr_add, two lanes at once).
@ __ctr2_add v256 cb i j → v256 {
    : i d << j 56
    ^ ( nurl_v256_add32 cb ( nurl_v256_set64 0 d 0 d ) )
}

// The counter pair (c, c+1), each the nonce words then the counter
// big-endian.
@ __ctr2_blk i n0 i n1 i n2 i c → v256 { ^ ( nurl_v256_join128 ( __ctr_blk n0 n1 n2 c ) ( __ctr_blk n0 n1 n2 + c 1 ) ) }

// Sixteen ciphertext blocks at `c` folded into `acc` with one
// reduction: pair j times the powers at entry 2j (H^(16-2j), H^(15-2j)).
// The products are spelled out rather than __ghw2_acc calls, so this is
// itself a tier function (see __ghw2_finish).
unsafe @ __ghw_fold16 v128 acc * u c * u gp → v128 {
    : v256 z ( nurl_v256_zero )
    : ~ v256 lo z
    : ~ v256 hi z
    : ~ v256 md z
    : ~ i j 0
    ~ < j 8 {
        : v256 x0 ( nurl_v256_bswap128 ( nurl_v256_ld # s + # i c * j 32 ) )
        : v256 x ? == j 0 ( nurl_v256_xor x0 ( nurl_v256_join128 acc ( nurl_v128_zero ) ) ) x0
        : v256 g ( nurl_v256_ld # s + # i gp * j 32 )
        = lo ( nurl_v256_xor lo ( nurl_v256_clmul_ll x g ) )
        = hi ( nurl_v256_xor hi ( nurl_v256_clmul_hh x g ) )
        = md ( nurl_v256_xor md ( nurl_v256_xor ( nurl_v256_clmul_lh x g ) ( nurl_v256_clmul_hl x g ) ) )
        = j + j 1
    }
    ^ ( __ghw2_finish lo hi md )
}

// The stitched loop body: sixteen CTR blocks (counters ctr .. ctr+15,
// from `inp` into `op`) and the GHASH fold of the sixteen ciphertext
// blocks at `prev` — the step before — into `acc`, interleaved round by
// round as in __gcm_hw_stitch8: rounds 1..7 fold pairs 1..7, and pair
// 0, the one carrying the accumulator, goes in round 8, so the step
// before's reduction has seven rounds to finish first.
//
// Two things differ from the eight-block kernel, both for the vector
// ports the AES rounds share (VPCLMULQDQ, the byte shuffles and the
// lane inserts all want port 5). The fold is unconditional: the first
// step folds whatever `prev` points at and the caller drops the answer
// — a branch around each fold block splits the step into basic blocks
// the instruction scheduler cannot interleave across, and LLVM grouped
// all four products ahead of the first round. And the first counter
// pair `cb` is carried from step to step by a byte add (inout), where
// building it from the scalar counter costs two byte swaps and three
// inserts a step; it is rebuilt only when its low byte would carry.
unsafe @ __gcm_vaes_stitch16 * u rk2 i nr i n0 i n1 i n2 i ctr inout v256 cb * u inp * u op v128 acc * u prev * u gp → v128 {
    : v256 k0 ( nurl_v256_ld # s rk2 )
    : ~ v256 b0 cb
    : ~ v256 b1 b0
    : ~ v256 b2 b0
    : ~ v256 b3 b0
    : ~ v256 b4 b0
    : ~ v256 b5 b0
    : ~ v256 b6 b0
    : ~ v256 b7 b0
    ? <= & ctr 255 240 {
        = b1 ( __ctr2_add b0 2 )
        = b2 ( __ctr2_add b0 4 )
        = b3 ( __ctr2_add b0 6 )
        = b4 ( __ctr2_add b0 8 )
        = b5 ( __ctr2_add b0 10 )
        = b6 ( __ctr2_add b0 12 )
        = b7 ( __ctr2_add b0 14 )
    } {
        = b1 ( __ctr2_blk n0 n1 n2 + ctr 2 )
        = b2 ( __ctr2_blk n0 n1 n2 + ctr 4 )
        = b3 ( __ctr2_blk n0 n1 n2 + ctr 6 )
        = b4 ( __ctr2_blk n0 n1 n2 + ctr 8 )
        = b5 ( __ctr2_blk n0 n1 n2 + ctr 10 )
        = b6 ( __ctr2_blk n0 n1 n2 + ctr 12 )
        = b7 ( __ctr2_blk n0 n1 n2 + ctr 14 )
    }
    = b0 ( nurl_v256_xor b0 k0 )
    = b1 ( nurl_v256_xor b1 k0 )
    = b2 ( nurl_v256_xor b2 k0 )
    = b3 ( nurl_v256_xor b3 k0 )
    = b4 ( nurl_v256_xor b4 k0 )
    = b5 ( nurl_v256_xor b5 k0 )
    = b6 ( nurl_v256_xor b6 k0 )
    = b7 ( nurl_v256_xor b7 k0 )
    = cb ? <= & ctr 255 236 ( __ctr2_add cb 16 ) ( __ctr2_blk n0 n1 n2 + ctr 16 )
    : v256 z ( nurl_v256_zero )
    : ~ v256 lo z
    : ~ v256 hi z
    : ~ v256 md z
    : ~ i r 1
    ~ < r 9 {
        ( __aes_round16 ( nurl_v256_ld # s + # i rk2 * r 32 ) b0 b1 b2 b3 b4 b5 b6 b7 )
        : i j ? == r 8 0 r
        : v256 x0 ( nurl_v256_bswap128 ( nurl_v256_ld # s + # i prev * j 32 ) )
        : v256 x ? == j 0 ( nurl_v256_xor x0 ( nurl_v256_join128 acc ( nurl_v128_zero ) ) ) x0
        ( __ghw2_acc x # *u + # i gp * j 32 lo hi md )
        = r + r 1
    }
    ( __aes_round16 ( nurl_v256_ld # s + # i rk2 288 ) b0 b1 b2 b3 b4 b5 b6 b7 )
    ? == nr 14 {
        ( __aes_round16 ( nurl_v256_ld # s + # i rk2 320 ) b0 b1 b2 b3 b4 b5 b6 b7 )
        ( __aes_round16 ( nurl_v256_ld # s + # i rk2 352 ) b0 b1 b2 b3 b4 b5 b6 b7 )
        ( __aes_round16 ( nurl_v256_ld # s + # i rk2 384 ) b0 b1 b2 b3 b4 b5 b6 b7 )
        ( __aes_round16 ( nurl_v256_ld # s + # i rk2 416 ) b0 b1 b2 b3 b4 b5 b6 b7 )
    } {}
    : v256 kl ( nurl_v256_ld # s + # i rk2 * nr 32 )
    ( nurl_v256_st # s op ( nurl_v256_xor ( nurl_v256_aesenclast b0 kl ) ( nurl_v256_ld # s inp ) ) )
    ( nurl_v256_st # s + # i op 32 ( nurl_v256_xor ( nurl_v256_aesenclast b1 kl ) ( nurl_v256_ld # s + # i inp 32 ) ) )
    ( nurl_v256_st # s + # i op 64 ( nurl_v256_xor ( nurl_v256_aesenclast b2 kl ) ( nurl_v256_ld # s + # i inp 64 ) ) )
    ( nurl_v256_st # s + # i op 96 ( nurl_v256_xor ( nurl_v256_aesenclast b3 kl ) ( nurl_v256_ld # s + # i inp 96 ) ) )
    ( nurl_v256_st # s + # i op 128 ( nurl_v256_xor ( nurl_v256_aesenclast b4 kl ) ( nurl_v256_ld # s + # i inp 128 ) ) )
    ( nurl_v256_st # s + # i op 160 ( nurl_v256_xor ( nurl_v256_aesenclast b5 kl ) ( nurl_v256_ld # s + # i inp 160 ) ) )
    ( nurl_v256_st # s + # i op 192 ( nurl_v256_xor ( nurl_v256_aesenclast b6 kl ) ( nurl_v256_ld # s + # i inp 192 ) ) )
    ( nurl_v256_st # s + # i op 224 ( nurl_v256_xor ( nurl_v256_aesenclast b7 kl ) ( nurl_v256_ld # s + # i inp 224 ) ) )
    ^ ( __ghw2_finish lo hi md )
}

// The wide kernel's tail: the last `rem` bytes (1 to 255) from `inp`
// to `op` from counter `ctr`, a pair of blocks at a time, and their
// GHASH folded into `acc` with one reduction — block j of the m left
// times H^(m-j), so pair p starts at power entry 16 - m + 2p. A short
// last pair goes through the 32 bytes at `pad`, zero-padded, which is
// also what makes a missing second block of it contribute nothing. Each
// pair's input is read before its output is written, so `op` may be
// `inp`; the GHASH input is the ciphertext — the output when sealing,
// with the keystream past a short pair's bytes cleared.
unsafe @ __gcm_vaes_tail * u rk2 i nr i n0 i n1 i n2 i ctr * u inp * u op i sealing i rem v128 acc * u gp * u pad → v128 {
    : i m / + rem 15 16
    : v256 z ( nurl_v256_zero )
    : ~ v256 lo z
    : ~ v256 hi z
    : ~ v256 md z
    : ~ i p 0
    ~ < * p 32 rem {
        : i o * p 32
        // The pair through the cipher, spelled out so this is itself a
        // tier function (see __ghw2_finish).
        : ~ v256 ks ( nurl_v256_xor ( __ctr2_blk n0 n1 n2 + ctr * p 2 ) ( nurl_v256_ld # s rk2 ) )
        : ~ i r 1
        ~ < r nr { = ks ( nurl_v256_aesenc ks ( nurl_v256_ld # s + # i rk2 * r 32 ) ) = r + r 1 }
        = ks ( nurl_v256_aesenclast ks ( nurl_v256_ld # s + # i rk2 * nr 32 ) )
        : i nb ? < - rem o 32 - rem o 32
        : ~ v256 v z
        ? == nb 32 { = v ( nurl_v256_ld # s + # i inp o ) } {
            ( nurl_v256_st # s pad z )
            ( nurl_memcpy # s pad # s + # i inp o nb )
            = v ( nurl_v256_ld # s pad )
        }
        : v256 y ( nurl_v256_xor v ks )
        : ~ v256 c v
        ? == sealing 1 {
            ? == nb 32 { = c y } {
                ( nurl_v256_st # s pad y )
                ( nurl_memset # s + # i pad nb 0 - 32 nb )
                = c ( nurl_v256_ld # s pad )
            }
        } {}
        : v256 x0 ( nurl_v256_bswap128 c )
        : v256 x ? == p 0 ( nurl_v256_xor x0 ( nurl_v256_join128 acc ( nurl_v128_zero ) ) ) x0
        : i e * 16 + - 16 m * p 2
        ( __ghw2_acc x # *u + # i gp e lo hi md )
        ? == nb 32 { ( nurl_v256_st # s + # i op o y ) } {
            ( nurl_v256_st # s pad y )
            ( nurl_memcpy # s + # i op o # s pad nb )
        }
        = p + p 1
    }
    ^ ( __ghw2_finish lo hi md )
}

// The AAD's GHASH for the wide kernels, from zero: blocks through
// __ghw_take, one reduction per eight (a TLS record's 5- or 13-byte AAD
// is one block, one reduction), a short last block zero-padded.
unsafe @ __ghw_aad * u aadp i aadlen * u gt → v128 {
    : v128 z ( nurl_v128_zero )
    : ~ v128 acc z
    : ~ v128 lo z
    : ~ v128 hi z
    : ~ v128 md z
    : ~ i rem / + aadlen 15 16
    : ~ i p ? > rem 8 8 rem
    : ~ i off 0
    ~ < off aadlen {
        : v128 x ( nurl_v128_ldn # s + # i aadp off - aadlen off )
        ( __ghw_take ( nurl_v128_bswap128 x ) gt acc lo hi md p rem )
        = off + off 16
    }
    ^ acc
}

// One AES-GCM pass on the wide path: the contract of __gcm_hw_run, for
// a key with the wide state and a message of at least 256 bytes.
// Marked `simd` so its helpers inline: it calls VAES-tier functions, so
// it is compiled once, for that tier, and gated on it.
unsafe simd @ __gcm_vaes_run * u hk i nr * u nonce * u aadp i aadlen * u inp i n * u op i sealing * u tagp * u pad → v {
    : *u gt # *u + # i hk * 16 + nr 1
    : *u rk2 # *u + # i hk ( __gcm_vaes_at nr )
    : *u gp # *u + # i rk2 * 32 + nr 1
    : v128 g1 ( nurl_v128_ld # s + # i gt 112 )
    : i n0 # i ( __ld32le nonce 0 )
    : i n1 # i ( __ld32le nonce 4 )
    : i n2 # i ( __ld32le nonce 8 )
    : v128 ej0 ( __aes_hw_enc1 hk nr ( __ctr_blk n0 n1 n2 1 ) )
    : ~ v128 acc ( __ghw_aad aadp aadlen gt )
    : ~ i off 0
    : ~ i ctr 2
    : ~ v256 cb ( __ctr2_blk n0 n1 n2 2 )
    ~ <= + off 256 n {
        // Sealing, a step folds the step before's ciphertext (the first
        // one folds its own input for nothing, and its answer is
        // dropped: __gcm_vaes_stitch16); opening, its own input, which
        // every load reads before the stores — so `op` may be `inp`.
        : *u prev ? & == sealing 1 > off 0 # *u + # i op - off 256 # *u + # i inp off
        : v128 a2 ( __gcm_vaes_stitch16 rk2 nr n0 n1 n2 ctr cb # *u + # i inp off # *u + # i op off acc prev gp )
        = acc ? | == sealing 0 > off 0 a2 acc
        = off + off 256
        = ctr + ctr 16
    }
    ? & == sealing 1 > off 0 { = acc ( __ghw_fold16 acc # *u + # i op - off 256 gp ) } {}
    ? < off n {
        = acc ( __gcm_vaes_tail rk2 nr n0 n1 n2 ctr # *u + # i inp off # *u + # i op off sealing - n off acc gp pad )
    } {}
    = acc ( __ghw_mul ( nurl_v128_xor acc ( nurl_v128_set64 * n 8 * aadlen 8 ) ) g1 )
    ( nurl_v128_st # s tagp ( nurl_v128_xor ( nurl_v128_bswap128 acc ) ej0 ) )
}

// ── AVX-512 path: VAES + VPCLMULQDQ on zmm ──────────────────────
// Where the CPU has the AVX-512 VAES tier (nurl_cpu_has_vaes512: Ice
// Lake server, Sapphire Rapids, Zen 4 and later) the bulk loop runs on
// v512 — four blocks a register, so the same sixteen-block step is four
// registers, and every VPCLMULQDQ does four products. Not for more AES:
// a zmm VAESENC issues on one port where a ymm one has two, so both do
// four blocks a cycle. For everything else — half the instructions to
// decode, half the products' issue slots, the XORs and shuffles that
// share AES's vector ports — measured on Sapphire Rapids at ~1.25× the
// ymm loop (and on par with OpenSSL's AVX-512 kernel), with the clock
// effects of 512-bit code in the number. It uses the wide key state as
// it is (round keys broadcast from the narrow schedule; the power
// table's 64-byte rows), and the ymm kernel's fold and tail.

// A quadruple fold's four lanes reduced and added together: the value
// __ghw2_finish's reduction gives for the lanes' sum, by fewer vector
// operations. With 512-bit work in flight, port 1 runs no vector
// operations, so every one this saves is half a cycle a step.
//
// That reduction, for the sum's lo, md, hi, is
//     t0 = lo ^ (md.0 into qword 1),  t1 = hi ^ (md.1 into qword 0)
//     u  = t0.0·Q,                   w  = t0 ^ swap(u)
//     r  = t1 ^ w ^ w.1·Q
// (Q = 0xC2 << 56, swap exchanges a lane's two qwords). Write m for
// md ^ u. Then w.1 = lo.1 ^ m.0 and r = hi ^ lo ^ swap(m) ^ (lo.1 ^
// m.0)·Q. Every term but swap(m) is a product or an XOR, so it is
// computed on all four lanes in place. A lane sum commutes with swap,
// so m is swapped only once, after its lanes are added. The lanes are
// added twice (r's terms and m) where __ghw2_finish adds three
// accumulators.
@ __ghw4_finish v512 lo4 v512 hi4 v512 md4 → v128 {
    : v512 q4 ( nurl_v512_bcast128 ( nurl_v128_set64 0xC200000000000000 0 ) )
    : v512 m ( nurl_v512_xor md4 ( nurl_v512_clmul_ll lo4 q4 ) )
    : v512 v ( nurl_v512_xor ( nurl_v512_clmul_hl lo4 q4 ) ( nurl_v512_clmul_ll m q4 ) )
    : v512 r ( nurl_v512_xor ( nurl_v512_xor hi4 lo4 ) v )
    : v256 r2 ( nurl_v256_xor ( nurl_v512_lo256 r ) ( nurl_v512_hi256 r ) )
    : v256 m2 ( nurl_v256_xor ( nurl_v512_lo256 m ) ( nurl_v512_hi256 m ) )
    : v128 r1 ( nurl_v128_xor ( nurl_v256_lo128 r2 ) ( nurl_v256_hi128 r2 ) )
    : v128 m1 ( nurl_v128_xor ( nurl_v256_lo128 m2 ) ( nurl_v256_hi128 m2 ) )
    ^ ( nurl_v128_xor r1 ( nurl_v128_rotlanes2 m1 ) )
}

// One AES round on sixteen blocks, four per register.
@ __aes_round16x4 v512 k inout v512 b0 inout v512 b1 inout v512 b2 inout v512 b3 → v {
    = b0 ( nurl_v512_aesenc b0 k )
    = b1 ( nurl_v512_aesenc b1 k )
    = b2 ( nurl_v512_aesenc b2 k )
    = b3 ( nurl_v512_aesenc b3 k )
}

// One quadruple of a fold, as __ghw2_acc: blocks 4j .. 4j+3 times the
// four powers at `g`.
unsafe @ __ghw4_acc v512 x * u g inout v512 lo inout v512 hi inout v512 md → v {
    : v512 gv ( nurl_v512_ld # s g )
    = lo ( nurl_v512_xor lo ( nurl_v512_clmul_ll x gv ) )
    = hi ( nurl_v512_xor hi ( nurl_v512_clmul_hh x gv ) )
    = md ( nurl_v512_xor md ( nurl_v512_xor ( nurl_v512_clmul_lh x gv ) ( nurl_v512_clmul_hl x gv ) ) )
}

// Sixteen blocks held in four registers, folded into `acc` with one
// reduction: quadruple j times the four powers at entry 4j.
unsafe @ __ghw4_fold v128 acc v512 c0 v512 c1 v512 c2 v512 c3 * u gp → v128 {
    : v512 z ( nurl_v512_zero )
    : ~ v512 lo z
    : ~ v512 hi z
    : ~ v512 md z
    : v512 a4 ( nurl_v512_join256 ( nurl_v256_join128 acc ( nurl_v128_zero ) ) ( nurl_v256_zero ) )
    ( __ghw4_acc ( nurl_v512_xor ( nurl_v512_bswap128 c0 ) a4 ) gp lo hi md )
    ( __ghw4_acc ( nurl_v512_bswap128 c1 ) # *u + # i gp 64 lo hi md )
    ( __ghw4_acc ( nurl_v512_bswap128 c2 ) # *u + # i gp 128 lo hi md )
    ( __ghw4_acc ( nurl_v512_bswap128 c3 ) # *u + # i gp 192 lo hi md )
    ^ ( __ghw4_finish lo hi md )
}

// Counter quadruple c+j .. c+j+3 from quadruple c's `cb` by a byte add,
// valid while no low byte carries (__ctr2_add).
@ __ctr4_add v512 cb i j → v512 { ^ ( nurl_v512_add32 cb ( nurl_v512_bcast128 ( nurl_v128_set32 0 0 0 << j 24 ) ) ) }

// The counter quadruple (c .. c+3).
@ __ctr4_blk i n0 i n1 i n2 i c → v512 { ^ ( nurl_v512_join256 ( __ctr2_blk n0 n1 n2 c ) ( __ctr2_blk n0 n1 n2 + c 2 ) ) }

// __gcm_vaes_stitch16 on zmm, with its unconditional fold and carried
// counters: sixteen CTR blocks and the fold of the sixteen blocks in
// c0 .. c3, the fold's four quadruples in rounds 2, 4, 6 and — the one
// carrying the accumulator — 8. The round keys come from the narrow
// schedule at `rk`, broadcast to all four lanes. On return c0 .. c3
// hold the sixteen blocks written to `op`.
//
// The blocks to fold come in registers, not from memory. Sealing, they
// are the step before's ciphertext, and reading that back from `op`
// means loading 64 bytes that were stored a few dozen cycles earlier.
// A TLS record's payload starts 5 bytes into its buffer, so each of
// those stores straddles two cache lines. A split store cannot forward
// to a load, so every load waited for its store to reach L1, and that
// cost 3–7 % of a sealed 16 KB record on Sapphire Rapids.
unsafe @ __gcm_vaes512_stitch16 * u rk i nr i n0 i n1 i n2 i ctr inout v512 cb * u inp * u op v128 acc inout v512 c0 inout v512 c1 inout v512 c2 inout v512 c3 * u gp → v128 {
    : v512 k0 ( nurl_v512_bcast128 ( nurl_v128_ld # s rk ) )
    : ~ v512 b0 cb
    : ~ v512 b1 b0
    : ~ v512 b2 b0
    : ~ v512 b3 b0
    ? <= & ctr 255 240 {
        = b1 ( __ctr4_add b0 4 )
        = b2 ( __ctr4_add b0 8 )
        = b3 ( __ctr4_add b0 12 )
    } {
        = b1 ( __ctr4_blk n0 n1 n2 + ctr 4 )
        = b2 ( __ctr4_blk n0 n1 n2 + ctr 8 )
        = b3 ( __ctr4_blk n0 n1 n2 + ctr 12 )
    }
    = b0 ( nurl_v512_xor b0 k0 )
    = b1 ( nurl_v512_xor b1 k0 )
    = b2 ( nurl_v512_xor b2 k0 )
    = b3 ( nurl_v512_xor b3 k0 )
    = cb ? <= & ctr 255 236 ( __ctr4_add cb 16 ) ( __ctr4_blk n0 n1 n2 + ctr 16 )
    : v512 z ( nurl_v512_zero )
    : ~ v512 lo z
    : ~ v512 hi z
    : ~ v512 md z
    : ~ i r 1
    ~ < r 9 {
        ( __aes_round16x4 ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk * r 16 ) ) b0 b1 b2 b3 )
        ? == 0 & r 1 {
            : i j ? == r 8 0 / r 2
            : v512 x0 ( nurl_v512_bswap128 ? == j 0 c0 ? == j 1 c1 ? == j 2 c2 c3 )
            : v512 x ? == j 0 ( nurl_v512_xor x0 ( nurl_v512_join256 ( nurl_v256_join128 acc ( nurl_v128_zero ) ) ( nurl_v256_zero ) ) ) x0
            ( __ghw4_acc x # *u + # i gp * j 64 lo hi md )
        } {}
        = r + r 1
    }
    // Round 9, then 10..13 for a 256-bit key, spelled out as in
    // __gcm_hw_stitch8.
    ( __aes_round16x4 ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk 144 ) ) b0 b1 b2 b3 )
    ? == nr 14 {
        ( __aes_round16x4 ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk 160 ) ) b0 b1 b2 b3 )
        ( __aes_round16x4 ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk 176 ) ) b0 b1 b2 b3 )
        ( __aes_round16x4 ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk 192 ) ) b0 b1 b2 b3 )
        ( __aes_round16x4 ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk 208 ) ) b0 b1 b2 b3 )
    } {}
    : v512 kl ( nurl_v512_bcast128 ( nurl_v128_ld # s + # i rk * nr 16 ) )
    = c0 ( nurl_v512_xor ( nurl_v512_aesenclast b0 kl ) ( nurl_v512_ld # s inp ) )
    = c1 ( nurl_v512_xor ( nurl_v512_aesenclast b1 kl ) ( nurl_v512_ld # s + # i inp 64 ) )
    = c2 ( nurl_v512_xor ( nurl_v512_aesenclast b2 kl ) ( nurl_v512_ld # s + # i inp 128 ) )
    = c3 ( nurl_v512_xor ( nurl_v512_aesenclast b3 kl ) ( nurl_v512_ld # s + # i inp 192 ) )
    ( nurl_v512_st # s op c0 )
    ( nurl_v512_st # s + # i op 64 c1 )
    ( nurl_v512_st # s + # i op 128 c2 )
    ( nurl_v512_st # s + # i op 192 c3 )
    ^ ( __ghw4_finish lo hi md )
}

// One AES-GCM pass on the AVX-512 path: __gcm_vaes_run with the bulk
// loop on zmm. `simd` for the reason that one is.
unsafe simd @ __gcm_vaes512_run * u hk i nr * u nonce * u aadp i aadlen * u inp i n * u op i sealing * u tagp * u pad → v {
    : *u gt # *u + # i hk * 16 + nr 1
    : *u rk2 # *u + # i hk ( __gcm_vaes_at nr )
    : *u gp # *u + # i rk2 * 32 + nr 1
    : v128 g1 ( nurl_v128_ld # s + # i gt 112 )
    : i n0 # i ( __ld32le nonce 0 )
    : i n1 # i ( __ld32le nonce 4 )
    : i n2 # i ( __ld32le nonce 8 )
    : v128 ej0 ( __aes_hw_enc1 hk nr ( __ctr_blk n0 n1 n2 1 ) )
    : ~ v128 acc ( __ghw_aad aadp aadlen gt )
    : ~ i off 0
    : ~ i ctr 2
    : ~ v512 cb ( __ctr4_blk n0 n1 n2 2 )
    // The blocks a step folds: sealing, the step before's output, which
    // the stitch leaves here (all zero before the first step, whose fold
    // is then dropped); opening, the step's own input, read before any
    // store, so `op` may be `inp`.
    : v512 z ( nurl_v512_zero )
    : ~ v512 c0 z
    : ~ v512 c1 z
    : ~ v512 c2 z
    : ~ v512 c3 z
    ~ <= + off 256 n {
        : *u ip # *u + # i inp off
        ? == sealing 0 {
            = c0 ( nurl_v512_ld # s ip )
            = c1 ( nurl_v512_ld # s + # i ip 64 )
            = c2 ( nurl_v512_ld # s + # i ip 128 )
            = c3 ( nurl_v512_ld # s + # i ip 192 )
        } {}
        : v128 a2 ( __gcm_vaes512_stitch16 hk nr n0 n1 n2 ctr cb ip # *u + # i op off acc c0 c1 c2 c3 gp )
        = acc ? | == sealing 0 > off 0 a2 acc
        = off + off 256
        = ctr + ctr 16
    }
    ? & == sealing 1 > off 0 { = acc ( __ghw4_fold acc c0 c1 c2 c3 gp ) } {}
    ? < off n {
        = acc ( __gcm_vaes_tail rk2 nr n0 n1 n2 ctr # *u + # i inp off # *u + # i op off sealing - n off acc gp pad )
    } {}
    = acc ( __ghw_mul ( nurl_v128_xor acc ( nurl_v128_set64 * n 8 * aadlen 8 ) ) g1 )
    ( nurl_v128_st # s tagp ( nurl_v128_xor ( nurl_v128_bswap128 acc ) ej0 ) )
}

// ── Per-key context ──────────────────────────────────────────────
// Everything that depends only on the key: the bitsliced round keys,
// the round count, and the GHASH subkey H = E_K(0^128) (the last 16
// bytes of `skey`, at __hsub_at nr). Built once by `aes_gcm_key_new`,
// reused by every seal/open/block call, released by its last owner. The
// per-call scratch (counter blocks, keystream, GHASH state) lives in the
// output's spare capacity — it is per message, not per key.
: AesGcmKeyImpl {
    ( Vec u ) skey
    i nr
    // The hardware path's key state (round keys + GHASH powers, layout
    // above) when the CPU has the crypto tier; empty otherwise — and
    // then `skey` is the software key, which a hardware key leaves empty.
    ( Vec u ) hkey
    // Which kernel a long message runs on: 1 the eight-block AES-NI one,
    // 2 the ymm VAES one, 3 the zmm one (the key then carries the wide
    // state); 0 for a software key.
    i tier
}

// A handle on the key state in an rcbox (stdlib/core/rcbox.nu): every
// copy is the same key, and the last owner releases it. `ctl` 0 is the
// null key a bad key length gets.
: AesGcmKey { ( Shared AesGcmKeyImpl ) ctl }

@ AesGcmKey_share AesGcmKey h → AesGcmKey { ^ @ AesGcmKey { ( shared_clone [AesGcmKeyImpl] . h ctl ) } }

@ AesGcmKey_drop sink AesGcmKey h → v {}

@ __AesGcmKey_ptr AesGcmKey h → *AesGcmKeyImpl { ^ ( shared_ptr [AesGcmKeyImpl] . h ctl ) }

// F for the null key `aes_gcm_key_new` returns on a bad key length.
@ aes_gcm_key_ok AesGcmKey h → b { ^ != 0 # i . h ctl }

@ aes_gcm_key_new ( Vec u ) key → AesGcmKey {
    : i klen ( vec_len [u] key )
    ? & != klen 16 != klen 32 { ^ @ AesGcmKey { ( shared_null [AesGcmKeyImpl] ) } } {}
    ^ ( _aes_gcm_key_tier key 3 )
}

// The best crypto tier this CPU has: 3 AVX-512 VAES, 2 VAES, 1 AES-NI,
// 0 none.
@ __aes_cpu_tier → i {
    ? ( nurl_cpu_has_vaes512 ) { ^ 3 } {}
    ? ( nurl_cpu_has_vaes ) { ^ 2 } {}
    ? ( nurl_cpu_has_aes ) { ^ 1 } {}
    ^ 0
}

// The kernel aes_gcm_key_new's keys run on this CPU, by name: `vaes512`,
// `vaes`, `aesni` or `software` — the tier above, after any NURL_CPU_*=0
// masking. For reports and diagnostics (bench/tls_bench records it).
@ aes_gcm_cpu_tier → s {
    : i t ( __aes_cpu_tier )
    ^ ? == t 3 `vaes512` ? == t 2 `vaes` ? == t 1 `aesni` `software`
}

// The key aes_gcm_key_new builds on a CPU whose best crypto tier is
// `tier` (0 software, 1 AES-NI, 2 VAES, 3 AVX-512 VAES) — or on this
// one, where it has less. aes_gcm_key_new asks for the best; the tests
// ask for each in turn, so one machine runs every kernel it can against
// the software oracle (aes_gcm_hw_agree.nu).
@ _aes_gcm_key_tier ( Vec u ) key i tier → AesGcmKey {
    : i klen ( vec_len [u] key )
    ? & != klen 16 != klen 32 { ^ @ AesGcmKey { ( shared_null [AesGcmKeyImpl] ) } } {}
    : i have ( __aes_cpu_tier )
    : i t ? < tier have tier have
    ? == t 0 { ^ ( _aes_gcm_key_sw key ) } {}
    : i nr ( __aes_nr key )
    : i wlen ? >= t 2 ( __gcm_vaes_len nr ) 0
    : ( Vec u ) hk ( vec_zeroed [u] + + * 16 + nr 1 256 wlen )
    ( __gcm_hw_init ( vec_data [u] key ) klen ( vec_data [u] hk ) )
    ? >= t 2 { ( __gcm_vaes_init ( vec_data [u] hk ) nr ) } {}
    ^ @ AesGcmKey { ( shared_new [AesGcmKeyImpl] @ AesGcmKeyImpl { ( vec_new [u] ) nr hk t } ) }
}

// The software key (bitsliced cipher, software GHASH) whatever the CPU
// has: what aes_gcm_key_new builds without the crypto tier, and the
// oracle the tests hold the hardware path to.
@ _aes_gcm_key_sw ( Vec u ) key → AesGcmKey {
    : i klen ( vec_len [u] key )
    ? & != klen 16 != klen 32 { ^ @ AesGcmKey { ( shared_null [AesGcmKeyImpl] ) } } {}
    : i nr ( __aes_nr key )
    : ( Vec u ) rk ( __aes_expand key )
    // One scratch block: the cipher's 8 words, then the all-zero input
    // and the output of one four-block call.
    : ( Vec u ) scr ( vec_zeroed [u] 192 )
    : s q # s ( vec_data [u] scr )
    : ( Vec u ) skey ( __skey_bitslice rk nr q )
    // H = E_K(0): slot 0 of one four-block call on an all-zero input.
    : *u zb # *u + # i q 64
    : *u hb # *u + # i q 128
    : *u skp ( vec_data [u] skey )
    ( __aes_ct64_enc4 zb hb # s skp nr q )
    ( nurl_memcpy # s + # i skp ( __hsub_at nr ) # s hb 16 )
    ^ @ AesGcmKey { ( shared_new [AesGcmKeyImpl] @ AesGcmKeyImpl { skey nr ( vec_new [u] ) 0 } ) }
}

// Let go of `k` now rather than at the end of its owner's scope.
@ aes_gcm_key_free sink AesGcmKey k → v {}

// One raw AES block: the 16 bytes of `block` encrypted under the key.
// QUIC header protection (RFC 9001 §5.4.3) is AES-ECB of the 16-byte
// sample; the four-block core runs with slot 0 live and the rest zero.
@ aes_block_encrypt AesGcmKey k__h ( Vec u ) block → ( Vec u ) {
    ? | == 0 # i . k__h ctl != ( vec_len [u] block ) 16 { ^ ( vec_new [u] ) } {}
    : *AesGcmKeyImpl k ( __AesGcmKey_ptr k__h )
    ? > ( vec_len [u] . k hkey ) 0 {
        : ( Vec u ) hout ( vec_zeroed [u] 16 )
        ( __aes_hw_block ( vec_data [u] . k hkey ) . k nr ( vec_data [u] block ) ( vec_data [u] hout ) )
        ^ hout
    } {}
    // the cipher's 8 words, then the input and output blocks
    : ( Vec u ) scr ( vec_zeroed [u] 192 )
    : s q # s ( vec_data [u] scr )
    : *u inb # *u + # i q 64
    : *u outb # *u + # i q 128
    : ~ i i 0
    ~ < i 16 { = . inb i # u ( __aes_bget block i ) = i + i 1 }
    ( __aes_ct64_enc4 inb outb # s ( vec_data [u] . k skey ) . k nr q )
    : ( Vec u ) out ( vec_with_cap [u] 16 )
    = i 0
    ~ < i 16 { ( vec_push [u] out . outb i ) = i + i 1 }
    ^ out
}

// One CTR pass plus the tag, on raw memory: `n` bytes from `inp` to `op`
// — `op` may be `inp`, so a record can be sealed or opened where it lies
// — under the 12-byte nonce at `np`, the tag over the CIPHERTEXT (`op`
// when sealing, `inp` when opening) written to `scr` + 208.
//
// `scr` is __gcm_scratch bytes, 16-aligned, overlapping none of the
// others: the software path's cipher words [0, 64), counter blocks
// [64, 128), keystream [128, 192), E_K(J0) [192, 208), the tag
// [208, 224) and the GHASH state and length block [224, 256); the
// hardware path's tag [208, 224) and tail keystream [224, 352) (the wide
// kernels' short-pair pad [224, 256)); and a
// nonce the in-place callers build [352, 364).
//
// The software path's first four-block call carries J0 = nonce ‖
// 0x00000001 in slot 0 (its ciphertext masks the tag) and counters 2..4
// in slots 1..3, so no block of the core is wasted; every later call is
// four counters. Opening, the tag is taken before the CTR pass, while
// `inp` still holds the ciphertext.
@ __gcm_scratch → i { ^ 368 }

// Where a call's scratch starts in a buffer whose data ends at `n`:
// 16-aligned and past room for the 16-byte tag a seal appends, so that
// append never regrows the buffer or lands on the scratch.
@ __gcm_scr_at i n → i { ^ & + n 31 -16 }

unsafe @ __gcm_core * AesGcmKeyImpl k * u np * u aadp i aadlen * u inp i n * u op i sealing * u scr → v {
    ? > ( vec_len [u] . k hkey ) 0 {
        : *u hk ( vec_data [u] . k hkey )
        : *u tagp # *u + # i scr 208
        : *u ks # *u + # i scr 224
        // A wide kernel for a message of a sixteen-block step or more,
        // on a key that has its state; the eight-block one otherwise.
        ? & >= n 256 >= . k tier 2 {
            ? == . k tier 3 {
                ( __gcm_vaes512_run hk . k nr np aadp aadlen inp n op sealing tagp ks )
            } {
                ( __gcm_vaes_run hk . k nr np aadp aadlen inp n op sealing tagp ks )
            }
            ^ v
        } {}
        ( __gcm_hw_run hk . k nr np aadp aadlen inp n op sealing tagp ks )
        ^ v
    } {}
    : *u skp ( vec_data [u] . k skey )
    : s skey # s skp
    : i nr . k nr
    ( nurl_memset # s scr 0 256 )
    : s q # s scr
    : *u cb # *u + # i scr 64
    : *u kb # *u + # i scr 128
    : *u tagp # *u + # i scr 208

    // The counter blocks all carry the same nonce; only the last four
    // bytes change, so the nonce is written once and left alone.
    : ~ i bi 0
    ~ < bi 4 {
        ( nurl_memcpy # s + # i cb * bi 16 # s np 12 )
        = bi + bi 1
    }

    // Batch 1: counters 1 (= J0), 2, 3, 4.
    ( __ctr_fill cb 1 )
    ( __aes_ct64_enc4 cb kb skey nr q )
    : *u ej0 # *u + # i scr 192
    : ~ i hi 0
    ~ < hi 16 { = . ej0 hi . kb hi = hi + hi 1 }
    : *u hp # *u + # i skp ( __hsub_at nr )
    : s gs # s + # i scr 224
    ? == sealing 0 { ( __gcm_tag_raw hp ej0 aadp aadlen inp n tagp gs ) } {}

    : i lim0 ? < n 48 n 48
    : ~ i j 0
    ~ < j lim0 {
        = . op j # u ^^ # i . inp j # i . kb + 16 j
        = j + j 1
    }
    : ~ i off lim0
    : ~ i ctr 5
    ~ < off n {
        ( __ctr_fill cb ctr )
        ( __aes_ct64_enc4 cb kb skey nr q )
        : i lim ? < - n off 64 - n off 64
        = j 0
        ~ < j lim {
            = . op + off j # u ^^ # i . inp + off j # i . kb j
            = j + j 1
        }
        = off + off 64
        = ctr + ctr 4
    }
    ? == sealing 1 { ( __gcm_tag_raw hp ej0 aadp aadlen op n tagp gs ) } {}
}

// One pass into a new Vec of `n` bytes, the call's scratch in its spare
// capacity — one allocation per call.
@ __gcm_run * AesGcmKeyImpl k ( Vec u ) nonce ( Vec u ) aad * u inp i n i sealing → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] + ( __gcm_scr_at n ) ( __gcm_scratch ) )
    : b _ol ( vec_set_len [u] out n )
    : *u op ( vec_data [u] out )
    ( __gcm_core k ( vec_data [u] nonce ) ( vec_data [u] aad ) ( vec_len [u] aad ) inp n op sealing # *u + # i op ( __gcm_scr_at n ) )
    ^ out
}

// AES-GCM seal under a prepared key: ciphertext with the 16-byte tag
// appended. Nonce must be 12 bytes; the plaintext cap is GCM's
// 2^39−256 bits = 2^36−32 bytes.
@ aes_gcm_seal AesGcmKey k__h ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → ( Vec u ) {
    ? | == 0 # i . k__h ctl != ( vec_len [u] nonce ) 12 { ^ ( vec_new [u] ) } {}
    ? > ( vec_len [u] pt ) 68719476704 { ^ ( vec_new [u] ) } {}
    : i n ( vec_len [u] pt )
    : ( Vec u ) ct ( __gcm_run ( __AesGcmKey_ptr k__h ) nonce aad ( vec_data [u] pt ) n 1 )
    // the tag the run left in the scratch, appended within capacity
    ( bytes_extend_raw ct # s + # i ( vec_data [u] ct ) + ( __gcm_scr_at n ) 208 16 )
    ^ ct
}

// Constant-time comparison of the 16-byte tags at `a` and `b`.
@ __tag16_eq * u a * u b → b {
    : ~ i diff 0
    : ~ i i 0
    ~ < i 16 { = diff | diff ^^ # i . a i # i . b i = i + i 1 }
    ^ == diff 0
}

// AES-GCM open under a prepared key: `ct_tag` is ciphertext followed by
// its 16-byte tag. The tag is verified BEFORE the plaintext is handed
// back, and the comparison is a constant-time OR-accumulate.
@ aes_gcm_open AesGcmKey k__h ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_tag → ?( Vec u ) {
    ? | == 0 # i . k__h ctl != ( vec_len [u] nonce ) 12 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : i total ( vec_len [u] ct_tag )
    ? < total 16 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : i ctlen - total 16
    : *u ctp ( vec_data [u] ct_tag )
    : ( Vec u ) pt ( __gcm_run ( __AesGcmKey_ptr k__h ) nonce aad ctp ctlen 0 )
    : *u tagp # *u + # i ( vec_data [u] pt ) + ( __gcm_scr_at ctlen ) 208
    ? ! ( __tag16_eq tagp # *u + # i ctp ctlen ) { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    ^ @ ?( Vec u ) { T pt }
}

// ── In place, with a sequence-number nonce ─────────────────────────
// What a record layer wants: the record sealed or opened where it lies
// in its own buffer, no Vec per record, and the nonce derived from the
// connection's static `iv` (12 bytes) and the record's sequence number —
// the 64-bit `seq` big-endian, XORed into the iv's last 8 bytes (TLS 1.3,
// RFC 8446 §5.3; QUIC, RFC 9001 §5.3). The scratch is the buffer's spare
// capacity past its length, reserved here.

// The nonce for (iv, seq) at `np`.
@ __seq_nonce ( Vec u ) iv i seq * u np → v {
    : *u ivp ( vec_data [u] iv )
    : ~ i b 0
    ~ < b 4 { = . np b . ivp b = b + b 1 }
    ~ < b 12 {
        = . np b # u ^^ # i . ivp b & >> seq * 8 - 11 b 255
        = b + b 1
    }
}

// Seal `buf[data_at, len)` in place, the AAD `buf[aad_at, data_at)`, and
// append the 16-byte tag. F — and `buf` untouched — for a null key, an
// iv that is not 12 bytes, offsets out of order, or a plaintext past
// GCM's cap.
@ aes_gcm_seal_in AesGcmKey k__h ( Vec u ) iv i seq ( Vec u ) buf i aad_at i data_at → b {
    : i len ( vec_len [u] buf )
    ? | | == 0 # i . k__h ctl != ( vec_len [u] iv ) 12 | | < aad_at 0 > aad_at data_at > data_at len { ^ F } {}
    : i n - len data_at
    ? > n 68719476704 { ^ F } {}
    : i at ( __gcm_scr_at len )
    ( vec_reserve [u] buf + - at len ( __gcm_scratch ) )
    : *u base ( vec_data [u] buf )
    : *u scr # *u + # i base at
    : *u np # *u + # i scr 352
    ( __seq_nonce iv seq np )
    : *u dp # *u + # i base data_at
    ( __gcm_core ( __AesGcmKey_ptr k__h ) np # *u + # i base aad_at - data_at aad_at dp n dp 1 scr )
    ( bytes_extend_raw buf # s + # i scr 208 16 )
    ^ T
}

// Open `buf[data_at, end)` — ciphertext, then its 16-byte tag — in
// place: on T, `buf[data_at, end - 16)` is the plaintext; the AAD is
// `buf[aad_at, data_at)` and bytes past `end` are left alone. On F (a
// wrong tag, or the same argument errors as aes_gcm_seal_in) the range
// is zeroed, never left as unauthenticated plaintext.
@ aes_gcm_open_in AesGcmKey k__h ( Vec u ) iv i seq ( Vec u ) buf i aad_at i data_at i end → b {
    : i len ( vec_len [u] buf )
    ? | | == 0 # i . k__h ctl != ( vec_len [u] iv ) 12 | | < aad_at 0 > aad_at data_at | | < end 16 > end len > data_at - end 16 { ^ F } {}
    : i n - - end data_at 16
    : i at ( __gcm_scr_at len )
    ( vec_reserve [u] buf + - at len ( __gcm_scratch ) )
    : *u base ( vec_data [u] buf )
    : *u scr # *u + # i base at
    : *u np # *u + # i scr 352
    ( __seq_nonce iv seq np )
    : *u dp # *u + # i base data_at
    ( __gcm_core ( __AesGcmKey_ptr k__h ) np # *u + # i base aad_at - data_at aad_at dp n dp 0 scr )
    ? ( __tag16_eq # *u + # i scr 208 # *u + # i dp n ) { ^ T } {}
    ( nurl_memset # s dp 0 n )
    ^ F
}

// One-shot seal/open: a context for this call only.
@ __gcm_seal ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) pt → ( Vec u ) {
    : AesGcmKey k ( aes_gcm_key_new key )
    ^ ( aes_gcm_seal k nonce aad pt )
}

@ __gcm_open ( Vec u ) key ( Vec u ) nonce ( Vec u ) aad ( Vec u ) ct_tag → ?( Vec u ) {
    : AesGcmKey k ( aes_gcm_key_new key )
    ^ ( aes_gcm_open k nonce aad ct_tag )
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
