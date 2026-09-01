// stdlib/std/p256_scalar.nu — constant-width arithmetic mod the NIST
// P-256 GROUP ORDER n (the "scalar field"), for ECDSA signing.
//
// ECDSA's point arithmetic is mod the prime p (stdlib/std/p256_field.nu,
// already a fast fixed-width Montgomery field). Its SCALAR arithmetic —
// r·d, z+r·d, and above all k⁻¹, all mod n — used to run on the generic
// variable-length std/bigint.nu, where k⁻¹ is a 256-iteration Fermat
// exponentiation that clones a heap magnitude every step. On a TLS 1.3
// handshake that CertificateVerify signature was the single largest
// crypto cost — roughly half of it in bigint_rem / __mag_clone.
//
// This is the same treatment: four 64-bit limbs, Montgomery CIOS with
// nurl_umulhi, and Fermat inversion over that field. n has no
// p ≡ −1 (mod 2^64) shortcut, so the reduction uses the general
// Montgomery constant n0 = −n⁻¹ mod 2^64.
//
//   n   = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551
//   n0  = 0xccd1c8aaee00bc4f
//
// Public surface (all 32-byte big-endian `( Vec u )`, the shape ECDSA
// scalars travel in):
//   ( p256n_reduce_be x )     → x mod n
//   ( p256n_mulmod_be a b )   → a·b mod n
//   ( p256n_addmod_be a b )   → (a+b) mod n
//   ( p256n_inv_be a )        → a⁻¹ mod n   (a ≠ 0)

$ `stdlib/core/vec.nu`

// ── limb helpers ──────────────────────────────────────────────────
// A field element is four 64-bit limbs, little-endian, stored as i64 bit
// patterns in a length-4 ( Vec i ).
@ __sn_mag4 → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 4 )
    : b _l ( vec_set_len [i] v 4 )
    ^ v
}

@ __sn_cp ( Vec i ) dst ( Vec i ) src → v {
    : *i d ( vec_data [i] dst )
    : *i s ( vec_data [i] src )
    = . d 0 . s 0 = . d 1 . s 1 = . d 2 . s 2 = . d 3 . s 3
}

// R^2 mod n — multiply by this (Montgomery) to enter the domain.
@ __sn_rr → ( Vec i ) {
    : ( Vec i ) v ( __sn_mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x83244c95be79eea2
    = . q 1 # i 0x4699799c49bd6fa6
    = . q 2 # i 0x2845b2392b6bec59
    = . q 3 # i 0x66e12d94f3d95620
    ^ v
}

// 1 in Montgomery form (= R mod n).
@ __sn_one_mont → ( Vec i ) {
    : ( Vec i ) v ( __sn_mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x0c46353d039cdaaf
    = . q 1 # i 0x4319055258e8617b
    = . q 2 # i 0
    = . q 3 # i 0xffffffff
    ^ v
}

// 1 in plain form.
@ __sn_one → ( Vec i ) {
    : ( Vec i ) v ( __sn_mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 1 = . q 1 # i 0 = . q 2 # i 0 = . q 3 # i 0
    ^ v
}

// ── Montgomery multiply, radix 2^64, general CIOS ─────────────────
// dst ← a·b·R^-1 mod n. Each a[j]·b[i] and m·n[j] is a full 64×64→128
// product via nurl_umulhi; the reduction multiplier is m = t0·n0 (n0 is
// not 1 here, unlike the prime field). `dst` may alias a or b.
@ __sn_mul ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : u64 a0 # u64 . ap 0
    : u64 a1 # u64 . ap 1
    : u64 a2 # u64 . ap 2
    : u64 a3 # u64 . ap 3
    : u64 b0 # u64 . bp 0
    : u64 b1 # u64 . bp 1
    : u64 b2 # u64 . bp 2
    : u64 b3 # u64 . bp 3
    // Accumulator t[0..5], in registers. It used to live in a 48-byte
    // `nurl_zalloc` — one heap allocation and free per scalar multiply,
    // and every limb step a load and a store — while the two nested
    // loops re-derived `b[i]` and the modulus limb `n[j]` from a chain
    // of compares on each pass. Written out, the accumulator never
    // leaves registers, the constants become multiply operands, and the
    // allocator is not involved at all.
    : ~ u64 t0 0
    : ~ u64 t1 0
    : ~ u64 t2 0
    : ~ u64 t3 0
    : ~ u64 t4 0
    : ~ u64 t5 0
    : ~ u64 m 0
    : ~ u64 cr 0
    // ── round 0: t += a·b0, then one Montgomery reduction ──
    = cr ( nurl_mac_hi a0 b0 t0 0 )
    = t0 ( nurl_mac_lo a0 b0 t0 0 )
    : u64 q01 ( nurl_mac_lo a1 b0 t1 cr )
    = cr ( nurl_mac_hi a1 b0 t1 cr )
    = t1 q01
    : u64 q02 ( nurl_mac_lo a2 b0 t2 cr )
    = cr ( nurl_mac_hi a2 b0 t2 cr )
    = t2 q02
    : u64 q03 ( nurl_mac_lo a3 b0 t3 cr )
    = cr ( nurl_mac_hi a3 b0 t3 cr )
    = t3 q03
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    // m = t0 · (−n^-1 mod 2^64). Unlike the prime field, n0 is not 1
    // here, so the reduction multiplier costs a real multiply.
    = m * t0 0xccd1c8aaee00bc4f
    // j=0: the low word of t0 + m·n0 is 0 by construction — that IS
    // the reduction — so only the carry out of it survives.
    = cr ( nurl_mac_hi m 0xf3b9cac2fc632551 t0 0 )
    : u64 w01 ( nurl_mac_lo m 0xbce6faada7179e84 t1 cr )
    = cr ( nurl_mac_hi m 0xbce6faada7179e84 t1 cr )
    = t1 w01
    : u64 w02 ( nurl_mac_lo m 0xffffffffffffffff t2 cr )
    = cr ( nurl_mac_hi m 0xffffffffffffffff t2 cr )
    = t2 w02
    : u64 w03 ( nurl_mac_lo m 0xffffffff00000000 t3 cr )
    = cr ( nurl_mac_hi m 0xffffffff00000000 t3 cr )
    = t3 w03
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    = t0 t1 = t1 t2 = t2 t3 = t3 t4 = t4 t5 = t5 0
    // ── round 1: t += a·b1, then one Montgomery reduction ──
    = cr ( nurl_mac_hi a0 b1 t0 0 )
    = t0 ( nurl_mac_lo a0 b1 t0 0 )
    : u64 q11 ( nurl_mac_lo a1 b1 t1 cr )
    = cr ( nurl_mac_hi a1 b1 t1 cr )
    = t1 q11
    : u64 q12 ( nurl_mac_lo a2 b1 t2 cr )
    = cr ( nurl_mac_hi a2 b1 t2 cr )
    = t2 q12
    : u64 q13 ( nurl_mac_lo a3 b1 t3 cr )
    = cr ( nurl_mac_hi a3 b1 t3 cr )
    = t3 q13
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    // m = t0 · (−n^-1 mod 2^64). Unlike the prime field, n0 is not 1
    // here, so the reduction multiplier costs a real multiply.
    = m * t0 0xccd1c8aaee00bc4f
    // j=0: the low word of t0 + m·n0 is 0 by construction — that IS
    // the reduction — so only the carry out of it survives.
    = cr ( nurl_mac_hi m 0xf3b9cac2fc632551 t0 0 )
    : u64 w11 ( nurl_mac_lo m 0xbce6faada7179e84 t1 cr )
    = cr ( nurl_mac_hi m 0xbce6faada7179e84 t1 cr )
    = t1 w11
    : u64 w12 ( nurl_mac_lo m 0xffffffffffffffff t2 cr )
    = cr ( nurl_mac_hi m 0xffffffffffffffff t2 cr )
    = t2 w12
    : u64 w13 ( nurl_mac_lo m 0xffffffff00000000 t3 cr )
    = cr ( nurl_mac_hi m 0xffffffff00000000 t3 cr )
    = t3 w13
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    = t0 t1 = t1 t2 = t2 t3 = t3 t4 = t4 t5 = t5 0
    // ── round 2: t += a·b2, then one Montgomery reduction ──
    = cr ( nurl_mac_hi a0 b2 t0 0 )
    = t0 ( nurl_mac_lo a0 b2 t0 0 )
    : u64 q21 ( nurl_mac_lo a1 b2 t1 cr )
    = cr ( nurl_mac_hi a1 b2 t1 cr )
    = t1 q21
    : u64 q22 ( nurl_mac_lo a2 b2 t2 cr )
    = cr ( nurl_mac_hi a2 b2 t2 cr )
    = t2 q22
    : u64 q23 ( nurl_mac_lo a3 b2 t3 cr )
    = cr ( nurl_mac_hi a3 b2 t3 cr )
    = t3 q23
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    // m = t0 · (−n^-1 mod 2^64). Unlike the prime field, n0 is not 1
    // here, so the reduction multiplier costs a real multiply.
    = m * t0 0xccd1c8aaee00bc4f
    // j=0: the low word of t0 + m·n0 is 0 by construction — that IS
    // the reduction — so only the carry out of it survives.
    = cr ( nurl_mac_hi m 0xf3b9cac2fc632551 t0 0 )
    : u64 w21 ( nurl_mac_lo m 0xbce6faada7179e84 t1 cr )
    = cr ( nurl_mac_hi m 0xbce6faada7179e84 t1 cr )
    = t1 w21
    : u64 w22 ( nurl_mac_lo m 0xffffffffffffffff t2 cr )
    = cr ( nurl_mac_hi m 0xffffffffffffffff t2 cr )
    = t2 w22
    : u64 w23 ( nurl_mac_lo m 0xffffffff00000000 t3 cr )
    = cr ( nurl_mac_hi m 0xffffffff00000000 t3 cr )
    = t3 w23
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    = t0 t1 = t1 t2 = t2 t3 = t3 t4 = t4 t5 = t5 0
    // ── round 3: t += a·b3, then one Montgomery reduction ──
    = cr ( nurl_mac_hi a0 b3 t0 0 )
    = t0 ( nurl_mac_lo a0 b3 t0 0 )
    : u64 q31 ( nurl_mac_lo a1 b3 t1 cr )
    = cr ( nurl_mac_hi a1 b3 t1 cr )
    = t1 q31
    : u64 q32 ( nurl_mac_lo a2 b3 t2 cr )
    = cr ( nurl_mac_hi a2 b3 t2 cr )
    = t2 q32
    : u64 q33 ( nurl_mac_lo a3 b3 t3 cr )
    = cr ( nurl_mac_hi a3 b3 t3 cr )
    = t3 q33
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    // m = t0 · (−n^-1 mod 2^64). Unlike the prime field, n0 is not 1
    // here, so the reduction multiplier costs a real multiply.
    = m * t0 0xccd1c8aaee00bc4f
    // j=0: the low word of t0 + m·n0 is 0 by construction — that IS
    // the reduction — so only the carry out of it survives.
    = cr ( nurl_mac_hi m 0xf3b9cac2fc632551 t0 0 )
    : u64 w31 ( nurl_mac_lo m 0xbce6faada7179e84 t1 cr )
    = cr ( nurl_mac_hi m 0xbce6faada7179e84 t1 cr )
    = t1 w31
    : u64 w32 ( nurl_mac_lo m 0xffffffffffffffff t2 cr )
    = cr ( nurl_mac_hi m 0xffffffffffffffff t2 cr )
    = t2 w32
    : u64 w33 ( nurl_mac_lo m 0xffffffff00000000 t3 cr )
    = cr ( nurl_mac_hi m 0xffffffff00000000 t3 cr )
    = t3 w33
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    = t0 t1 = t1 t2 = t2 t3 = t3 t4 = t4 t5 = t5 0
    ( __sn_condsub dst t0 t1 t2 t3 t4 )
}

// Conditional subtract of n from a value held as (r0..r3, top word r4),
// which is < 2n. Writes the reduced four limbs into dst. `r4` is the
// carry word from the multiply's accumulator (0 or 1); together with a
// borrow past r3 it decides whether the value was ≥ n.
@ __sn_condsub ( Vec i ) dst u64 w0 u64 w1 u64 w2 u64 w3 u64 w4 → v {
    : u64 d0 ( nurl_subb_lo w0 0xf3b9cac2fc632551 0 )
    : ~ u64 bb ( nurl_subb_hi w0 0xf3b9cac2fc632551 0 )
    : u64 d1 ( nurl_subb_lo w1 0xbce6faada7179e84 bb )
    = bb ( nurl_subb_hi w1 0xbce6faada7179e84 bb )
    : u64 d2 ( nurl_subb_lo w2 0xffffffffffffffff bb )
    = bb ( nurl_subb_hi w2 0xffffffffffffffff bb )
    : u64 d3 ( nurl_subb_lo w3 0xffffffff00000000 bb )
    = bb ( nurl_subb_hi w3 0xffffffff00000000 bb )
    // topb < 0 ⇒ the value was < n ⇒ keep w; else take d = w − n.
    : i topb - # i w4 # i bb
    : u64 mask ? < topb 0 0 0xffffffffffffffff
    : u64 imask ^^ mask 0xffffffffffffffff
    : *i op ( vec_data [i] dst )
    = . op 0 # i | & mask d0 & imask w0
    = . op 1 # i | & mask d1 & imask w1
    = . op 2 # i | & mask d2 & imask w2
    = . op 3 # i | & mask d3 & imask w3
}

@ __sn_to_mont ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) rr ( __sn_rr )
    : ( Vec i ) o ( __sn_mag4 )
    ( __sn_mul o a rr )
    ( vec_free [i] rr )
    ^ o
}

@ __sn_from_mont ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) one ( __sn_one )
    : ( Vec i ) o ( __sn_mag4 )
    ( __sn_mul o a one )
    ( vec_free [i] one )
    ^ o
}

// ── byte <-> limb (32-byte big-endian) ────────────────────────────
@ _snbget ( Vec u ) v i k → i { ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ 0 } }

@ _snld_be ( Vec u ) v i off → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 8 { = acc | << acc 8 ( _snbget v + off k ) = k + k 1 }
    ^ acc
}

// 32 big-endian bytes → four little-endian limbs (no reduction).
@ __sn_from_be_raw ( Vec u ) be → ( Vec i ) {
    : ( Vec i ) v ( __sn_mag4 )
    : *i q ( vec_data [i] v )
    = . q 3 ( _snld_be be 0 )
    = . q 2 ( _snld_be be 8 )
    = . q 1 ( _snld_be be 16 )
    = . q 0 ( _snld_be be 24 )
    ^ v
}

// Reduce raw four limbs in [0, 2^256) modulo n (2^256 < 2n, one sub).
@ __sn_reduce ( Vec i ) v → v {
    : *i q ( vec_data [i] v )
    ( __sn_condsub v # u64 . q 0 # u64 . q 1 # u64 . q 2 # u64 . q 3 0 )
}

// Four little-endian limbs → 32 big-endian bytes.
@ __sn_to_be ( Vec i ) v → ( Vec u ) {
    : *i q ( vec_data [i] v )
    : ( Vec u ) o ( vec_with_cap [u] 32 )
    : b _l ( vec_set_len [u] o 32 )
    : *u op ( vec_data [u] o )
    : ~ i limb 3
    : ~ i pos 0
    ~ >= limb 0 {
        : u64 w # u64 . q limb
        : ~ i k 0
        ~ < k 8 { = . op + pos k # u & >> w * 8 - 7 k 255 = k + k 1 }
        = pos + pos 8
        = limb - limb 1
    }
    ^ o
}

// ── public: 32-byte big-endian in/out ─────────────────────────────
@ p256n_reduce_be ( Vec u ) x → ( Vec u ) {
    : ( Vec i ) v ( __sn_from_be_raw x )
    ( __sn_reduce v )
    : ( Vec u ) o ( __sn_to_be v )
    ( vec_free [i] v )
    ^ o
}

@ p256n_mulmod_be ( Vec u ) a ( Vec u ) b → ( Vec u ) {
    : ( Vec i ) av ( __sn_from_be_raw a ) ( __sn_reduce av )
    : ( Vec i ) bv ( __sn_from_be_raw b ) ( __sn_reduce bv )
    : ( Vec i ) am ( __sn_to_mont av )
    : ( Vec i ) bm ( __sn_to_mont bv )
    : ( Vec i ) pm ( __sn_mag4 )
    ( __sn_mul pm am bm )
    : ( Vec i ) pr ( __sn_from_mont pm )
    : ( Vec u ) o ( __sn_to_be pr )
    ( vec_free [i] av ) ( vec_free [i] bv ) ( vec_free [i] am )
    ( vec_free [i] bm ) ( vec_free [i] pm ) ( vec_free [i] pr )
    ^ o
}

@ p256n_addmod_be ( Vec u ) a ( Vec u ) b → ( Vec u ) {
    : ( Vec i ) av ( __sn_from_be_raw a ) ( __sn_reduce av )
    : ( Vec i ) bv ( __sn_from_be_raw b ) ( __sn_reduce bv )
    : *i xp ( vec_data [i] av )
    : *i yp ( vec_data [i] bv )
    : ( Vec i ) s ( __sn_mag4 )
    : *i sp ( vec_data [i] s )
    : ~ u64 cy 0
    : ~ i k 0
    ~ < k 4 {
        : u64 x # u64 . xp k
        : u64 s1 + x # u64 . yp k
        : u64 s2 + s1 cy
        = . sp k # i s2
        = cy + ? < s1 x 1 0 ? < s2 s1 1 0
        = k + k 1
    }
    ( __sn_condsub s # u64 . sp 0 # u64 . sp 1 # u64 . sp 2 # u64 . sp 3 cy )
    : ( Vec u ) o ( __sn_to_be s )
    ( vec_free [i] av ) ( vec_free [i] bv ) ( vec_free [i] s )
    ^ o
}

// n − 2, big-endian.
@ __sn_nm2_be → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] 32 )
    : b _l ( vec_set_len [u] v 32 )
    : *u q ( vec_data [u] v )
    = . q 0 # u 0xff = . q 1 # u 0xff = . q 2 # u 0xff = . q 3 # u 0xff
    = . q 4 # u 0x00 = . q 5 # u 0x00 = . q 6 # u 0x00 = . q 7 # u 0x00
    = . q 8 # u 0xff = . q 9 # u 0xff = . q 10 # u 0xff = . q 11 # u 0xff
    = . q 12 # u 0xff = . q 13 # u 0xff = . q 14 # u 0xff = . q 15 # u 0xff
    = . q 16 # u 0xbc = . q 17 # u 0xe6 = . q 18 # u 0xfa = . q 19 # u 0xad
    = . q 20 # u 0xa7 = . q 21 # u 0x17 = . q 22 # u 0x9e = . q 23 # u 0x84
    = . q 24 # u 0xf3 = . q 25 # u 0xb9 = . q 26 # u 0xca = . q 27 # u 0xc2
    = . q 28 # u 0xfc = . q 29 # u 0x63 = . q 30 # u 0x25 = . q 31 # u 0x4f
    ^ v
}

// Flat 15-entry window table: entry k (1-based) at [ (k−1)·4, (k−1)·4+4 ).
@ __sn_tbl_put ( Vec i ) tbl i k ( Vec i ) v → v {
    : *i tp ( vec_data [i] tbl )
    : *i vp ( vec_data [i] v )
    : i base * - k 1 4
    = . tp + base 0 . vp 0
    = . tp + base 1 . vp 1
    = . tp + base 2 . vp 2
    = . tp + base 3 . vp 3
}

@ __sn_tbl_cp ( Vec i ) dst ( Vec i ) tbl i k → v {
    : *i tp ( vec_data [i] tbl )
    : *i dp ( vec_data [i] dst )
    : i base * - k 1 4
    = . dp 0 . tp + base 0
    = . dp 1 . tp + base 1
    = . dp 2 . tp + base 2
    = . dp 3 . tp + base 3
}

// a^-1 mod n, Fermat: a^(n-2) with a fixed 4-bit window, MSB→LSB.
// The exponent n−2 is a PUBLIC curve constant, so the schedule — and
// every branch below, which reads only that constant — is identical for
// all inputs; the data stays in branch-free Montgomery arithmetic. The
// old bit-at-a-time ladder cost 256 squarings + ~170 multiplies plus two
// 4-limb copies per bit; the window costs 14 (table) + 252 squarings +
// one multiply per non-zero nibble (~59) and no per-bit copies.
@ p256n_inv_be ( Vec u ) a → ( Vec u ) {
    : ( Vec i ) av ( __sn_from_be_raw a ) ( __sn_reduce av )
    : ( Vec i ) am ( __sn_to_mont av )
    : ( Vec u ) e ( __sn_nm2_be )
    // tbl[k] = a^k (Montgomery), k = 1..15
    : ( Vec i ) tbl ( vec_with_cap [i] 60 )
    : b _l ( vec_set_len [i] tbl 60 )
    : ( Vec i ) w ( __sn_mag4 )
    ( __sn_cp w am )
    ( __sn_tbl_put tbl 1 w )
    : ~ i k 2
    ~ <= k 15 {
        ( __sn_mul w w am )
        ( __sn_tbl_put tbl k w )
        = k + k 1
    }
    // first nibble of n−2 is 0xf; then 63 windows of 4 squarings + mul
    : ( Vec i ) r ( __sn_mag4 )
    ( __sn_tbl_cp r tbl 15 )
    : ~ i wi 1
    ~ < wi 64 {
        ( __sn_mul r r r ) ( __sn_mul r r r )
        ( __sn_mul r r r ) ( __sn_mul r r r )
        : i byte # i ?? ( vec_get [u] e / wi 2 ) { T x → # i x F _ → 0 }
        : i nib ? == % wi 2 0 >> byte 4 & byte 15
        ? > nib 0 {
            ( __sn_tbl_cp w tbl nib )
            ( __sn_mul r r w )
        } {}
        = wi + wi 1
    }
    : ( Vec i ) out ( __sn_from_mont r )
    : ( Vec u ) o ( __sn_to_be out )
    ( vec_free [i] av ) ( vec_free [i] am ) ( vec_free [i] r )
    ( vec_free [u] e ) ( vec_free [i] tbl ) ( vec_free [i] w ) ( vec_free [i] out )
    ^ o
}
