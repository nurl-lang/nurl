// stdlib/std/p384_field.nu — fixed-width GF(p) / GF(n) arithmetic and
// point operations for NIST P-384, serving ECDSA *verification*.
//
// Everything here computes over PUBLIC data — a certificate's key, a
// signature's r/s, a message digest — so unlike std/p256_field (the
// constant-time secret-path field), the loops here are ordinary loops
// and the window reads are ordinary indexed loads. Do NOT route a
// private scalar through this module.
//
// The engine is a generic 6-limb (384-bit) Montgomery CIOS multiply over
// a modulus carried in the scratch, instantiated twice: once for the
// field prime p and once for the group order n. Each limb product is a
// full 64×64→128 `nurl_mac` (a·b + c + d in one primitive), the same
// wide-radix shape std/p256_field runs unrolled — looped here, because
// verification is not a per-connection steady-state cost the way the
// handshake's secret path is, and 6 unrolled limbs would be 2.5× the
// text for the last ~2× of a path that is already ~50× faster than the
// bigint one it replaces.
//
// Point addition is the Renes–Costello–Batina COMPLETE projective
// formula (the exact 40-step register schedule std/p256_field runs, with
// a and 3b as Montgomery operands) — correct for ALL inputs including
// P = Q, P = −Q and the identity, which is what makes the double-scalar
// sum u1·G + u2·Q safe against adversarially crafted signatures with no
// case analysis at all.
//
// Public surface (used by std/ecdsa_p256.nu's P-384 verify):
//   ( p384_ecdsa_verify_core z r s qx qy ) → b
// with all five inputs as 48-byte big-endian ( Vec u ); the caller has
// already range-checked r, s ∈ [1, n−1] and validated (qx, qy) on-curve.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`

// ── limb plumbing ─────────────────────────────────────────────────

// A 6-limb magnitude, uninitialised (filled through *i before any read).
@ _mag6 → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 6 )
    : b _l ( vec_set_len [i] v 6 )
    ^ v
}

@ _magn6 i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : b _l ( vec_set_len [i] v n )
    ^ v
}

// Big-endian bytes (any length ≤ 48) → 6 little-endian 64-bit limbs.
@ __m6_from_be ( Vec u ) src → ( Vec i ) {
    : i n ( vec_len [u] src )
    : ( Vec i ) out ( _mag6 )
    : *i op ( vec_data [i] out )
    : ~ i k 0
    ~ < k 6 {
        // limb k covers bytes [n−8(k+1), n−8k) of the big-endian view.
        : ~ u64 acc 0
        : ~ i j 0
        ~ < j 8 {
            : i pos - n + * 8 k - 8 j
            ? >= pos 0 {
                : u64 bj # u64 ?? ( vec_get [u] src pos ) { T b → # i b F _ → 0 }
                = acc | << acc 8 bj
            } {}
            = j + j 1
        }
        = . op k # i acc
        = k + k 1
    }
    ^ out
}

// 6 little-endian limbs → 48 big-endian bytes.
@ __m6_to_be48 ( Vec i ) v → ( Vec u ) {
    : *i q ( vec_data [i] v )
    : ( Vec u ) o ( vec_with_cap [u] 48 )
    : ~ i limb 5
    ~ >= limb 0 {
        : u64 w # u64 . q limb
        : ~ i sh 56
        ~ >= sh 0 {
            ( vec_push [u] o # u & # i >> w sh 255 )
            = sh - sh 8
        }
        = limb - limb 1
    }
    ^ o
}

// ── the Montgomery scratch ────────────────────────────────────────
// One engine, two instantiations: the modulus, its −md⁻¹ mod 2^64, and
// R² mod md ride in the scratch, plus every temporary the layers above
// need. Ownership mirrors std/p256_field: the field ops own acc/diff,
// the point layer owns g0..g5, the inversion chain owns gp — no `_d`
// worker calls another that wants the same register.
: P384Scr {
    ( Vec i ) md i n0 ( Vec i ) r2
    ( Vec i ) acc ( Vec i ) diff
    ( Vec i ) g0 ( Vec i ) g1 ( Vec i ) g2
    ( Vec i ) g3 ( Vec i ) g4 ( Vec i ) g5
    ( Vec i ) gp
}

@ __p384_scr_make ( Vec i ) md i n0 ( Vec i ) rsq → P384Scr {
    ^ @ P384Scr {
        md n0 rsq
        ( _magn6 8 ) ( _mag6 )
        ( _mag6 ) ( _mag6 ) ( _mag6 )
        ( _mag6 ) ( _mag6 ) ( _mag6 )
        ( _mag6 )
    }
}

@ __p384_scr_free P384Scr s → v {
    ( vec_free [i] . s md ) ( vec_free [i] . s r2 )
    ( vec_free [i] . s acc ) ( vec_free [i] . s diff )
    ( vec_free [i] . s g0 ) ( vec_free [i] . s g1 ) ( vec_free [i] . s g2 )
    ( vec_free [i] . s g3 ) ( vec_free [i] . s g4 ) ( vec_free [i] . s g5 )
    ( vec_free [i] . s gp )
}

// p = 2^384 − 2^128 − 2^96 + 2^32 − 1, little-endian 64-bit limbs.
@ __p384_mod_p → ( Vec i ) {
    : ( Vec i ) v ( _mag6 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x00000000FFFFFFFF = . q 1 # i 0xFFFFFFFF00000000
    = . q 2 # i 0xFFFFFFFFFFFFFFFE = . q 3 # i 0xFFFFFFFFFFFFFFFF
    = . q 4 # i 0xFFFFFFFFFFFFFFFF = . q 5 # i 0xFFFFFFFFFFFFFFFF
    ^ v
}

// R² mod p (R = 2^384).
@ __p384_r2_p → ( Vec i ) {
    : ( Vec i ) v ( _mag6 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0xFFFFFFFE00000001 = . q 1 # i 0x0000000200000000
    = . q 2 # i 0xFFFFFFFE00000000 = . q 3 # i 0x0000000200000000
    = . q 4 1 = . q 5 0
    ^ v
}

// n (the group order), little-endian limbs.
@ __p384_mod_n → ( Vec i ) {
    : ( Vec i ) v ( _mag6 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0xECEC196ACCC52973 = . q 1 # i 0x581A0DB248B0A77A
    = . q 2 # i 0xC7634D81F4372DDF = . q 3 # i 0xFFFFFFFFFFFFFFFF
    = . q 4 # i 0xFFFFFFFFFFFFFFFF = . q 5 # i 0xFFFFFFFFFFFFFFFF
    ^ v
}

// R² mod n.
@ __p384_r2_n → ( Vec i ) {
    : ( Vec i ) v ( _mag6 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x2D319B2419B409A9 = . q 1 # i 0xFF3D81E5DF1AA419
    = . q 2 # i 0xBC3E483AFCB82947 = . q 3 # i 0xD40D49174AAB1CC5
    = . q 4 # i 0x3FB05B7A28266895 = . q 5 # i 0x0C84EE012B39BF21
    ^ v
}

// Scratch over GF(p): −p⁻¹ mod 2^64 = 0x100000001.
@ __p384_pscr_new → P384Scr {
    ^ ( __p384_scr_make ( __p384_mod_p ) # i 0x0000000100000001 ( __p384_r2_p ) )
}

// Scratch over GF(n): −n⁻¹ mod 2^64.
@ __p384_nscr_new → P384Scr {
    ^ ( __p384_scr_make ( __p384_mod_n ) # i 0x6ED46089E88FDC45 ( __p384_r2_n ) )
}

// p − 2 (the Fermat-inverse exponent over GF(p)).
@ __p384_pm2 → ( Vec i ) {
    : ( Vec i ) v ( __p384_mod_p )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x00000000FFFFFFFD
    ^ v
}

// n − 2 (the Fermat-inverse exponent over GF(n)).
@ __p384_nm2 → ( Vec i ) {
    : ( Vec i ) v ( __p384_mod_n )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0xECEC196ACCC52971
    ^ v
}

// ── the engine ────────────────────────────────────────────────────

// dst = a·b·R⁻¹ mod md — Montgomery CIOS, 6 limbs, radix 2^64. The
// accumulator lives in scr.acc (8 words: 6 + 2 CIOS overflow words),
// the conditional-subtract staging in scr.diff, so `dst` may alias a
// and/or b — nothing is written to it until the final masked merge.
@ __m6_mul P384Scr scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i mp ( vec_data [i] . scr md )
    : *i tp ( vec_data [i] . scr acc )
    : u64 n0 # u64 . scr n0
    : ~ i z 0
    ~ < z 8 { = . tp z 0 = z + z 1 }
    : ~ i rnd 0
    ~ < rnd 6 {
        // t += a · b[rnd]
        : u64 bi # u64 . bp rnd
        : ~ u64 cr 0
        : ~ i j 0
        ~ < j 6 {
            : u64 aj # u64 . ap j
            : u64 tj # u64 . tp j
            : u64 lo ( nurl_mac_lo aj bi tj cr )
            = cr ( nurl_mac_hi aj bi tj cr )
            = . tp j # i lo
            = j + j 1
        }
        : u64 t6 # u64 . tp 6
        = . tp 6 # i ( nurl_addc_lo t6 cr 0 )
        = . tp 7 # i + # u64 . tp 7 ( nurl_addc_hi t6 cr 0 )
        // one Montgomery reduction: m = t0·n0; t = (t + m·md) / 2^64.
        // The low word of t0 + m·md[0] is 0 by construction — that IS
        // the reduction — so only its carry survives, and the divide by
        // 2^64 is fused into the j−1 store.
        : u64 m * # u64 . tp 0 n0
        = cr ( nurl_mac_hi m # u64 . mp 0 # u64 . tp 0 0 )
        : ~ i k 1
        ~ < k 6 {
            : u64 mk # u64 . mp k
            : u64 tk # u64 . tp k
            : u64 lo ( nurl_mac_lo m mk tk cr )
            = cr ( nurl_mac_hi m mk tk cr )
            = . tp - k 1 # i lo
            = k + k 1
        }
        : u64 t6b # u64 . tp 6
        = . tp 5 # i ( nurl_addc_lo t6b cr 0 )
        = . tp 6 # i + # u64 . tp 7 ( nurl_addc_hi t6b cr 0 )
        = . tp 7 0
        = rnd + rnd 1
    }
    // t[0..5] + top word t[6]: value < 2·md — one conditional subtract.
    : *i dp ( vec_data [i] . scr diff )
    : ~ u64 bb 0
    : ~ i j2 0
    ~ < j2 6 {
        : u64 tj # u64 . tp j2
        : u64 mj # u64 . mp j2
        = . dp j2 # i ( nurl_subb_lo tj mj bb )
        = bb ( nurl_subb_hi tj mj bb )
        = j2 + j2 1
    }
    : i topb - # i # u64 . tp 6 # i bb
    : u64 mask ? < topb 0 0 18446744073709551615
    : u64 imask ^^ mask 18446744073709551615
    : *i op ( vec_data [i] dst )
    : ~ i j3 0
    ~ < j3 6 {
        = . op j3 # i | & mask # u64 . dp j3 & imask # u64 . tp j3
        = j3 + j3 1
    }
}

// dst = (a + b) mod md. a, b < md ⇒ one conditional subtract. Alias-safe.
@ __m6_add P384Scr scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i mp ( vec_data [i] . scr md )
    : *i tp ( vec_data [i] . scr acc )
    : ~ u64 cc 0
    : ~ i j 0
    ~ < j 6 {
        : u64 aj # u64 . ap j
        : u64 bj # u64 . bp j
        = . tp j # i ( nurl_addc_lo aj bj cc )
        = cc ( nurl_addc_hi aj bj cc )
        = j + j 1
    }
    : *i dp ( vec_data [i] . scr diff )
    : ~ u64 bb 0
    : ~ i j2 0
    ~ < j2 6 {
        : u64 tj # u64 . tp j2
        : u64 mj # u64 . mp j2
        = . dp j2 # i ( nurl_subb_lo tj mj bb )
        = bb ( nurl_subb_hi tj mj bb )
        = j2 + j2 1
    }
    : i topb - # i cc # i bb
    : u64 mask ? < topb 0 0 18446744073709551615
    : u64 imask ^^ mask 18446744073709551615
    : *i op ( vec_data [i] dst )
    : ~ i j3 0
    ~ < j3 6 {
        = . op j3 # i | & mask # u64 . dp j3 & imask # u64 . tp j3
        = j3 + j3 1
    }
}

// dst = (a − b) mod md: subtract, and if it borrowed add md back. Alias-safe.
@ __m6_sub P384Scr scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i mp ( vec_data [i] . scr md )
    : *i dp ( vec_data [i] . scr diff )
    : ~ u64 bb 0
    : ~ i j 0
    ~ < j 6 {
        : u64 aj # u64 . ap j
        : u64 bj # u64 . bp j
        = . dp j # i ( nurl_subb_lo aj bj bb )
        = bb ( nurl_subb_hi aj bj bb )
        = j + j 1
    }
    : u64 mask ? == # i bb 0 0 18446744073709551615
    : *i op ( vec_data [i] dst )
    : ~ u64 cc 0
    : ~ i j2 0
    ~ < j2 6 {
        : u64 dj # u64 . dp j2
        : u64 pj & mask # u64 . mp j2
        = . op j2 # i ( nurl_addc_lo dj pj cc )
        = cc ( nurl_addc_hi dj pj cc )
        = j2 + j2 1
    }
}

// One conditional subtract of md, in place: brings any v < 2·md (e.g. a
// raw 384-bit big-endian load, since md > 2^383) into [0, md).
@ __m6_reduce_once P384Scr scr ( Vec i ) v → v {
    : *i vp ( vec_data [i] v )
    : *i mp ( vec_data [i] . scr md )
    : *i dp ( vec_data [i] . scr diff )
    : ~ u64 bb 0
    : ~ i j 0
    ~ < j 6 {
        : u64 aj # u64 . vp j
        : u64 mj # u64 . mp j
        = . dp j # i ( nurl_subb_lo aj mj bb )
        = bb ( nurl_subb_hi aj mj bb )
        = j + j 1
    }
    ? == # i bb 0 {
        : ~ i j2 0
        ~ < j2 6 { = . vp j2 . dp j2 = j2 + j2 1 }
    } {}
}

@ __m6_to_mont P384Scr scr ( Vec i ) dst ( Vec i ) a → v {
    ( __m6_mul scr dst a . scr r2 )
}

@ __m6_from_mont P384Scr scr ( Vec i ) dst ( Vec i ) a → v {
    : ( Vec i ) one ( _mag6 )
    : *i q ( vec_data [i] one )
    = . q 0 1 = . q 1 0 = . q 2 0 = . q 3 0 = . q 4 0 = . q 5 0
    ( __m6_mul scr dst a one )
    ( vec_free [i] one )
}

@ __m6_copy ( Vec i ) dst ( Vec i ) a → v {
    : *i op ( vec_data [i] dst )
    : *i ap ( vec_data [i] a )
    : ~ i j 0
    ~ < j 6 { = . op j . ap j = j + j 1 }
}

@ __m6_is_zero ( Vec i ) a → b {
    : *i ap ( vec_data [i] a )
    : ~ i acc 0
    : ~ i j 0
    ~ < j 6 { = acc | acc . ap j = j + j 1 }
    ^ == acc 0
}

// dst = a^e mod md (Montgomery in/out), square-and-multiply MSB→LSB over
// the 384-bit exponent `e` (6 plain limbs — a public constant here:
// md − 2, the Fermat inverse). dst must NOT alias a.
@ __m6_pow P384Scr scr ( Vec i ) dst ( Vec i ) a ( Vec i ) e → v {
    : *i ep ( vec_data [i] e )
    // dst = 1 in Montgomery form (R mod md = to_mont(1)).
    : ( Vec i ) one ( _mag6 )
    : *i q ( vec_data [i] one )
    = . q 0 1 = . q 1 0 = . q 2 0 = . q 3 0 = . q 4 0 = . q 5 0
    ( __m6_to_mont scr dst one )
    ( vec_free [i] one )
    : ~ i bit 383
    ~ >= bit 0 {
        ( __m6_mul scr dst dst dst )
        : i b1 & 1 # i >> # u64 . ep / bit 64 % bit 64
        ? != b1 0 { ( __m6_mul scr dst dst a ) } {}
        = bit - bit 1
    }
}

// ── points ────────────────────────────────────────────────────────
// Homogeneous projective (X : Y : Z), x = X/Z, identity = (0 : 1 : 0),
// coordinates in Montgomery form over GF(p).

: P384Pt { ( Vec i ) x ( Vec i ) y ( Vec i ) z }

@ __p384_pt_new → P384Pt {
    ^ @ P384Pt { ( _mag6 ) ( _mag6 ) ( _mag6 ) }
}

@ __p384_pt_free P384Pt p → v {
    ( vec_free [i] . p x ) ( vec_free [i] . p y ) ( vec_free [i] . p z )
}

@ __p384_set_identity P384Scr scr P384Pt pt → v {
    : *i xp ( vec_data [i] . pt x )
    : *i zp ( vec_data [i] . pt z )
    : ~ i j 0
    ~ < j 6 { = . xp j 0 = . zp j 0 = j + j 1 }
    : ( Vec i ) one ( _mag6 )
    : *i q ( vec_data [i] one )
    = . q 0 1 = . q 1 0 = . q 2 0 = . q 3 0 = . q 4 0 = . q 5 0
    ( __m6_to_mont scr . pt y one )
    ( vec_free [i] one )
}

@ __p384_pt_copy P384Pt dst P384Pt a → v {
    ( __m6_copy . dst x . a x )
    ( __m6_copy . dst y . a y )
    ( __m6_copy . dst z . a z )
}

// a = −3 mod p and b3 = 3·b mod p, both already in Montgomery form.
@ __p384_a_mont → ( Vec i ) {
    : ( Vec i ) v ( _mag6 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x00000003FFFFFFFC = . q 1 # i 0xFFFFFFFC00000000
    = . q 2 # i 0xFFFFFFFFFFFFFFFB = . q 3 # i 0xFFFFFFFFFFFFFFFF
    = . q 4 # i 0xFFFFFFFFFFFFFFFF = . q 5 # i 0xFFFFFFFFFFFFFFFF
    ^ v
}

@ __p384_b3_mont → ( Vec i ) {
    : ( Vec i ) v ( _mag6 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x18349952D7C38966 = . q 1 # i 0xE57D098B6EE498C4
    = . q 2 # i 0x67D661D14B60068E = . q 3 # i 0xA9A5E3CBBDBAA0A7
    = . q 4 # i 0x228165DC5D0661BE = . q 5 # i 0x671833E220EF3FED
    ^ v
}

// The generator's affine coordinates, plain (non-Montgomery) limbs.
@ __p384_gx_plain → ( Vec i ) {
    : ( Vec i ) v ( _mag6 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x3A545E3872760AB7 = . q 1 # i 0x5502F25DBF55296C
    = . q 2 # i 0x59F741E082542A38 = . q 3 # i 0x6E1D3B628BA79B98
    = . q 4 # i 0x8EB1C71EF320AD74 = . q 5 # i 0xAA87CA22BE8B0537
    ^ v
}

@ __p384_gy_plain → ( Vec i ) {
    : ( Vec i ) v ( _mag6 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x7A431D7C90EA0E5F = . q 1 # i 0x0A60B1CE1D7E819D
    = . q 2 # i 0xE9DA3113B5F0B8C0 = . q 3 # i 0xF8F41DBD289A147C
    = . q 4 # i 0x5D9E98BF9292DC29 = . q 5 # i 0x3617DE4A96262C6F
    ^ v
}

// Complete projective point addition — Renes–Costello–Batina, the exact
// 40-step register schedule std/p256_field.nu runs (see p256ct_padd_d
// there for the aliasing argument: X3 is first written after the last
// read of X1/X2, Y3 and Z3 after the last reads of Y1/Y2/Z1/Z2, so
// `dst` may alias P and/or Q). am / b3m are the Montgomery curve
// constants; the six working registers come from the scratch.
@ __p384_padd_d P384Scr scr P384Pt dst P384Pt P P384Pt Q ( Vec i ) am ( Vec i ) b3m → v {
    : ( Vec i ) X1 . P x : ( Vec i ) Y1 . P y : ( Vec i ) Z1 . P z
    : ( Vec i ) X2 . Q x : ( Vec i ) Y2 . Q y : ( Vec i ) Z2 . Q z
    : ( Vec i ) X3 . dst x : ( Vec i ) Y3 . dst y : ( Vec i ) Z3 . dst z
    : ( Vec i ) t0 . scr g0 : ( Vec i ) t1 . scr g1 : ( Vec i ) t2 . scr g2
    : ( Vec i ) t3 . scr g3 : ( Vec i ) t4 . scr g4 : ( Vec i ) t5 . scr g5
    ( __m6_mul scr t0 X1 X2 )  //  1
    ( __m6_mul scr t1 Y1 Y2 )  //  2
    ( __m6_mul scr t2 Z1 Z2 )  //  3
    ( __m6_add scr t3 X1 Y1 )  //  4
    ( __m6_add scr t4 X2 Y2 )  //  5
    ( __m6_mul scr t3 t3 t4 )  //  6
    ( __m6_add scr t4 t0 t1 )  //  7
    ( __m6_sub scr t3 t3 t4 )  //  8
    ( __m6_add scr t4 X1 Z1 )  //  9
    ( __m6_add scr t5 X2 Z2 )  // 10
    ( __m6_mul scr t4 t4 t5 )  // 11
    ( __m6_add scr t5 t0 t2 )  // 12
    ( __m6_sub scr t4 t4 t5 )  // 13
    ( __m6_add scr t5 Y1 Z1 )  // 14
    ( __m6_add scr X3 Y2 Z2 )  // 15
    ( __m6_mul scr t5 t5 X3 )  // 16
    ( __m6_add scr X3 t1 t2 )  // 17
    ( __m6_sub scr t5 t5 X3 )  // 18
    ( __m6_mul scr Z3 am t4 )  // 19
    ( __m6_mul scr X3 b3m t2 )  // 20
    ( __m6_add scr Z3 X3 Z3 )  // 21
    ( __m6_sub scr X3 t1 Z3 )  // 22
    ( __m6_add scr Z3 t1 Z3 )  // 23
    ( __m6_mul scr Y3 X3 Z3 )  // 24
    ( __m6_add scr t1 t0 t0 )  // 25
    ( __m6_add scr t1 t1 t0 )  // 26
    ( __m6_mul scr t2 am t2 )  // 27
    ( __m6_mul scr t4 b3m t4 )  // 28
    ( __m6_add scr t1 t1 t2 )  // 29
    ( __m6_sub scr t2 t0 t2 )  // 30
    ( __m6_mul scr t2 am t2 )  // 31
    ( __m6_add scr t4 t4 t2 )  // 32
    ( __m6_mul scr t0 t1 t4 )  // 33
    ( __m6_add scr Y3 Y3 t0 )  // 34
    ( __m6_mul scr t0 t5 t4 )  // 35
    ( __m6_mul scr X3 t3 X3 )  // 36
    ( __m6_sub scr X3 X3 t0 )  // 37
    ( __m6_mul scr t0 t3 t1 )  // 38
    ( __m6_mul scr Z3 t5 Z3 )  // 39
    ( __m6_add scr Z3 Z3 t0 )  // 40
}

// ── window tables ─────────────────────────────────────────────────
// Sixteen projective multiples 0·B … 15·B in one flat limb vector,
// entry d at [d·18, d·18+18) as x‖y‖z. Reads are plain indexed loads —
// the digits are public here (see the module header).

@ __p384_tbl_put ( Vec i ) tbl i d P384Pt p → v {
    : *i tp ( vec_data [i] tbl )
    : *i xp ( vec_data [i] . p x )
    : *i yp ( vec_data [i] . p y )
    : *i zp ( vec_data [i] . p z )
    : i base * d 18
    : ~ i k 0
    ~ < k 6 {
        = . tp + base k . xp k
        = . tp + + base 6 k . yp k
        = . tp + + base 12 k . zp k
        = k + k 1
    }
}

@ __p384_tbl_get P384Pt dst ( Vec i ) tbl i d → v {
    : *i tp ( vec_data [i] tbl )
    : *i xp ( vec_data [i] . dst x )
    : *i yp ( vec_data [i] . dst y )
    : *i zp ( vec_data [i] . dst z )
    : i base * d 18
    : ~ i k 0
    ~ < k 6 {
        = . xp k . tp + base k
        = . yp k . tp + + base 6 k
        = . zp k . tp + + base 12 k
        = k + k 1
    }
}

// Build the 16-entry window table for base point B (entry 0 = identity).
@ __p384_tbl_build P384Scr scr P384Pt B ( Vec i ) am ( Vec i ) b3m → ( Vec i ) {
    : ( Vec i ) tbl ( _magn6 288 )
    : P384Pt run ( __p384_pt_new )
    ( __p384_set_identity scr run )
    ( __p384_tbl_put tbl 0 run )
    ( __p384_tbl_put tbl 1 B )
    ( __p384_pt_copy run B )
    : ~ i d 2
    ~ < d 16 {
        ( __p384_padd_d scr run run B am b3m )
        ( __p384_tbl_put tbl d run )
        = d + d 1
    }
    ( __p384_pt_free run )
    ^ tbl
}

// ── the verify core ───────────────────────────────────────────────
// R = u1·G + u2·Q with u1 = z·s⁻¹, u2 = r·s⁻¹ (mod n), then
// r =? x(R) mod n. Straus double-scalar: ONE shared run of doublings,
// both scalars consumed four bits per window — 96 × (4 doublings +
// 2 table additions), every operation the complete formula.
//
// All five inputs are 48-byte big-endian; the caller has range-checked
// r, s ∈ [1, n−1] and validated (qx, qy) as an on-curve point < p.
@ p384_ecdsa_verify_core ( Vec u ) zb ( Vec u ) rb ( Vec u ) sb ( Vec u ) qxb ( Vec u ) qyb → b {
    // u1, u2 over GF(n). z (a truncated digest) can be ≥ n; one
    // conditional subtract reduces it, since z < 2^384 < 2n.
    : P384Scr ns ( __p384_nscr_new )
    : ( Vec i ) sl ( __m6_from_be sb )
    : ( Vec i ) zl ( __m6_from_be zb )
    : ( Vec i ) rl ( __m6_from_be rb )
    ( __m6_reduce_once ns sl )
    ( __m6_reduce_once ns zl )
    ( __m6_reduce_once ns rl )
    ( __m6_to_mont ns sl sl )
    ( __m6_to_mont ns zl zl )
    ( __m6_to_mont ns rl rl )
    : ( Vec i ) w ( _mag6 )
    : ( Vec i ) nm2 ( __p384_nm2 )
    ( __m6_pow ns w sl nm2 )
    ( vec_free [i] nm2 )
    ( __m6_mul ns zl zl w )
    ( __m6_mul ns rl rl w )
    ( __m6_from_mont ns zl zl )
    ( __m6_from_mont ns rl rl )
    : ( Vec u ) u1 ( __m6_to_be48 zl )
    : ( Vec u ) u2 ( __m6_to_be48 rl )
    ( vec_free [i] sl ) ( vec_free [i] zl ) ( vec_free [i] rl )
    ( vec_free [i] w )
    ( __p384_scr_free ns )

    // The points, over GF(p).
    : P384Scr fs ( __p384_pscr_new )
    : ( Vec i ) am ( __p384_a_mont )
    : ( Vec i ) b3m ( __p384_b3_mont )
    : P384Pt G ( __p384_pt_new )
    : ( Vec i ) gx ( __p384_gx_plain )
    : ( Vec i ) gy ( __p384_gy_plain )
    ( __m6_to_mont fs . G x gx )
    ( __m6_to_mont fs . G y gy )
    ( vec_free [i] gx ) ( vec_free [i] gy )
    : P384Pt Q ( __p384_pt_new )
    : ( Vec i ) qxl ( __m6_from_be qxb )
    : ( Vec i ) qyl ( __m6_from_be qyb )
    ( __m6_to_mont fs . Q x qxl )
    ( __m6_to_mont fs . Q y qyl )
    ( vec_free [i] qxl ) ( vec_free [i] qyl )
    // Z = 1 in Montgomery form for both affine inputs.
    : ( Vec i ) one ( _mag6 )
    : *i q1 ( vec_data [i] one )
    = . q1 0 1 = . q1 1 0 = . q1 2 0 = . q1 3 0 = . q1 4 0 = . q1 5 0
    ( __m6_to_mont fs . G z one )
    ( __m6_to_mont fs . Q z one )

    : ( Vec i ) tg ( __p384_tbl_build fs G am b3m )
    : ( Vec i ) tq ( __p384_tbl_build fs Q am b3m )
    : P384Pt acc ( __p384_pt_new )
    : P384Pt ent ( __p384_pt_new )
    ( __p384_set_identity fs acc )
    : ~ i wdx 0
    ~ < wdx 96 {
        ( __p384_padd_d fs acc acc acc am b3m )
        ( __p384_padd_d fs acc acc acc am b3m )
        ( __p384_padd_d fs acc acc acc am b3m )
        ( __p384_padd_d fs acc acc acc am b3m )
        : i b1 ?? ( vec_get [u] u1 / wdx 2 ) { T b → # i b F _ → 0 }
        : i b2 ?? ( vec_get [u] u2 / wdx 2 ) { T b → # i b F _ → 0 }
        : i d1 ? == % wdx 2 0 & 15 >> b1 4 & 15 b1
        : i d2 ? == % wdx 2 0 & 15 >> b2 4 & 15 b2
        ( __p384_tbl_get ent tg d1 )
        ( __p384_padd_d fs acc acc ent am b3m )
        ( __p384_tbl_get ent tq d2 )
        ( __p384_padd_d fs acc acc ent am b3m )
        = wdx + wdx 1
    }

    : ~ b result F
    ? ! ( __m6_is_zero . acc z ) {
        // x(R) = X/Z, out of Montgomery form, then mod n (one
        // conditional subtract: x < p < 2n) against r.
        : ( Vec i ) zinv ( _mag6 )
        : ( Vec i ) pm2 ( __p384_pm2 )
        ( __m6_pow fs zinv . acc z pm2 )
        ( vec_free [i] pm2 )
        ( __m6_mul fs . acc x . acc x zinv )
        ( __m6_from_mont fs . acc x . acc x )
        ( vec_free [i] zinv )
        : P384Scr ns2 ( __p384_nscr_new )
        ( __m6_reduce_once ns2 . acc x )
        ( __p384_scr_free ns2 )
        : ( Vec u ) xb ( __m6_to_be48 . acc x )
        = result ( bytes_eq xb rb )
        ( vec_free [u] xb )
    } {}

    ( vec_free [u] u1 ) ( vec_free [u] u2 )
    ( vec_free [i] one ) ( vec_free [i] tg ) ( vec_free [i] tq )
    ( vec_free [i] am ) ( vec_free [i] b3m )
    ( __p384_pt_free G ) ( __p384_pt_free Q )
    ( __p384_pt_free acc ) ( __p384_pt_free ent )
    ( __p384_scr_free fs )
    ^ result
}
