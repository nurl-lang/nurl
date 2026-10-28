// stdlib/std/modinv.nu — constant-time modular inverse for odd moduli
// below 2^256: Bernstein and Yang's divsteps ("Fast constant-time gcd
// computation and modular inversion", 2019), in the formulation of
// libsecp256k1's modinv64 (MIT): 59 divsteps at a time on the low words,
// then the 2×2 transition matrix applied to the full f, g and to the
// Bézout pair d, e. 590 divsteps reach g = 0 for every input below
// 2^256, so the walk is fixed: ten rounds, nothing branching on the
// value.
//
// Numbers in a round are in signed-62 form: five i64 limbs v0 … v4 worth
// Σ v_k·2^(62k), each in (−2^62, 2^62) (the top one may carry the sign).
// A modulus is given in that form too, its limbs chosen small where they
// can be (2^255 − 19 is −19 + 128·2^248), with m⁻¹ mod 2^62.
//
//   ( _modinv256 o0 o1 o2 o3 x0 x1 x2 x3 m0 m1 m2 m3 m4 minv )
//
// x (four little-endian words, x < m) ↦ x⁻¹ mod m in o (four words,
// fully reduced, < m); 0 ↦ 0, and an x sharing a factor with m gives a
// value that is not an inverse. x < m is the range the 590-step bound is
// proved for: callers reduce first. The products are 64 × 64 → 128 signed
// (nurl_smulhi), accumulated as a (low word, signed high word) pair.

$ `stdlib/core/vec.nu`

// acc ← acc + a·b, acc the signed 128-bit (lo, hi).
inline @ __mi_mac inout u64 lo inout i hi i a i b → v {
    : u64 pl # u64 * a b
    : i ph ( nurl_smulhi a b )
    : u64 s ( nurl_addc_lo lo pl 0 )
    : u64 c ( nurl_addc_hi lo pl 0 )
    = lo s
    = hi + + hi ph # i c
}

// acc ← acc >> 62, arithmetic.
inline @ __mi_shr inout u64 lo inout i hi → v {
    = lo | >> lo 62 << # u64 hi 2
    = hi >> hi 62
}

// 59 divsteps on the low words of f (odd) and g. zeta = −(δ + 1/2).
// Out: the transition matrix [u v; q r], scaled by 2^62, and the new
// zeta. Every step runs the same instructions: the two conditions are
// masks.
inline @ __mi_steps inout i zeta inout i tu inout i tv inout i tq inout i tr i f0 i g0 → v {
    : ~ u64 u 8
    : ~ u64 v 0
    : ~ u64 q 0
    : ~ u64 r 8
    : ~ u64 f # u64 f0
    : ~ u64 g # u64 g0
    : ~ i z zeta
    : ~ i k 3
    ~ < k 62 {
        // m1: zeta < 0; m2: g odd
        : u64 m1 # u64 >> z 63
        : u64 m2 - # u64 0 & g 1
        // x, y, w: f, u, v negated when zeta < 0; added to g, q, r when g is odd
        : u64 x - ^^ f m1 m1
        : u64 y - ^^ u m1 m1
        : u64 w - ^^ v m1 m1
        = g + g & x m2
        = q + q & y m2
        = r + r & w m2
        // both: zeta ← −zeta − 2, and g, q, r added to f, u, v (the swap)
        : u64 m3 & m1 m2
        = z - ^^ z # i m3 1
        = f + f & g m3
        = u + u & q m3
        = v + v & r m3
        = g >> g 1
        = u << u 1
        = v << v 1
        = k + k 1
    }
    = zeta z
    = tu # i u
    = tv # i v
    = tq # i q
    = tr # i r
}

// The constant-time inverse. m = Σ m_k 2^(62k) odd, minv = m⁻¹ mod 2^62.
inline @ _modinv256 inout u64 o0 inout u64 o1 inout u64 o2 inout u64 o3 u64 x0 u64 x1 u64 x2 u64 x3 i m0 i m1 i m2 i m3 i m4 u64 minv → v {
    : u64 M62 4611686018427387903
    // f = m, g = x (signed-62), d = 0, e = 1
    : ~ i f0 m0
    : ~ i f1 m1
    : ~ i f2 m2
    : ~ i f3 m3
    : ~ i f4 m4
    : ~ i g0 # i & x0 M62
    : ~ i g1 # i & | >> x0 62 << x1 2 M62
    : ~ i g2 # i & | >> x1 60 << x2 4 M62
    : ~ i g3 # i & | >> x2 58 << x3 6 M62
    : ~ i g4 # i >> x3 56
    : ~ i d0 0
    : ~ i d1 0
    : ~ i d2 0
    : ~ i d3 0
    : ~ i d4 0
    : ~ i e0 1
    : ~ i e1 0
    : ~ i e2 0
    : ~ i e3 0
    : ~ i e4 0
    : ~ i zeta -1
    : ~ i round 0
    ~ < round 10 {
        : ~ i u 0
        : ~ i v 0
        : ~ i q 0
        : ~ i r 0
        ( __mi_steps zeta u v q r f0 g0 )

        // d, e ← (t·[d, e] + m·[md, me]) / 2^62, md and me chosen so the
        // low 62 bits vanish (and starting from [u, q] / [v, r] when d / e
        // is negative, which keeps both in range).
        : i sd >> d4 63
        : i se >> e4 63
        : ~ i md + & u sd & v se
        : ~ i me + & q sd & r se
        : ~ u64 cdl 0
        : ~ i cdh 0
        : ~ u64 cel 0
        : ~ i ceh 0
        ( __mi_mac cdl cdh u d0 ) ( __mi_mac cdl cdh v e0 )
        ( __mi_mac cel ceh q d0 ) ( __mi_mac cel ceh r e0 )
        = md - md # i & + * minv cdl # u64 md M62
        = me - me # i & + * minv cel # u64 me M62
        ( __mi_mac cdl cdh m0 md ) ( __mi_mac cel ceh m0 me )
        ( __mi_shr cdl cdh ) ( __mi_shr cel ceh )
        ( __mi_mac cdl cdh u d1 ) ( __mi_mac cdl cdh v e1 ) ( __mi_mac cdl cdh m1 md )
        ( __mi_mac cel ceh q d1 ) ( __mi_mac cel ceh r e1 ) ( __mi_mac cel ceh m1 me )
        : i nd0 # i & cdl M62
        : i ne0 # i & cel M62
        ( __mi_shr cdl cdh ) ( __mi_shr cel ceh )
        ( __mi_mac cdl cdh u d2 ) ( __mi_mac cdl cdh v e2 ) ( __mi_mac cdl cdh m2 md )
        ( __mi_mac cel ceh q d2 ) ( __mi_mac cel ceh r e2 ) ( __mi_mac cel ceh m2 me )
        : i nd1 # i & cdl M62
        : i ne1 # i & cel M62
        ( __mi_shr cdl cdh ) ( __mi_shr cel ceh )
        ( __mi_mac cdl cdh u d3 ) ( __mi_mac cdl cdh v e3 ) ( __mi_mac cdl cdh m3 md )
        ( __mi_mac cel ceh q d3 ) ( __mi_mac cel ceh r e3 ) ( __mi_mac cel ceh m3 me )
        : i nd2 # i & cdl M62
        : i ne2 # i & cel M62
        ( __mi_shr cdl cdh ) ( __mi_shr cel ceh )
        ( __mi_mac cdl cdh u d4 ) ( __mi_mac cdl cdh v e4 ) ( __mi_mac cdl cdh m4 md )
        ( __mi_mac cel ceh q d4 ) ( __mi_mac cel ceh r e4 ) ( __mi_mac cel ceh m4 me )
        : i nd3 # i & cdl M62
        : i ne3 # i & cel M62
        ( __mi_shr cdl cdh ) ( __mi_shr cel ceh )
        = d0 nd0 = d1 nd1 = d2 nd2 = d3 nd3 = d4 # i cdl
        = e0 ne0 = e1 ne1 = e2 ne2 = e3 ne3 = e4 # i cel

        // f, g ← t·[f, g] / 2^62 (exact: the divsteps cleared 62 low bits)
        : ~ u64 cfl 0
        : ~ i cfh 0
        : ~ u64 cgl 0
        : ~ i cgh 0
        ( __mi_mac cfl cfh u f0 ) ( __mi_mac cfl cfh v g0 )
        ( __mi_mac cgl cgh q f0 ) ( __mi_mac cgl cgh r g0 )
        ( __mi_shr cfl cfh ) ( __mi_shr cgl cgh )
        ( __mi_mac cfl cfh u f1 ) ( __mi_mac cfl cfh v g1 )
        ( __mi_mac cgl cgh q f1 ) ( __mi_mac cgl cgh r g1 )
        : i nf0 # i & cfl M62
        : i ng0 # i & cgl M62
        ( __mi_shr cfl cfh ) ( __mi_shr cgl cgh )
        ( __mi_mac cfl cfh u f2 ) ( __mi_mac cfl cfh v g2 )
        ( __mi_mac cgl cgh q f2 ) ( __mi_mac cgl cgh r g2 )
        : i nf1 # i & cfl M62
        : i ng1 # i & cgl M62
        ( __mi_shr cfl cfh ) ( __mi_shr cgl cgh )
        ( __mi_mac cfl cfh u f3 ) ( __mi_mac cfl cfh v g3 )
        ( __mi_mac cgl cgh q f3 ) ( __mi_mac cgl cgh r g3 )
        : i nf2 # i & cfl M62
        : i ng2 # i & cgl M62
        ( __mi_shr cfl cfh ) ( __mi_shr cgl cgh )
        ( __mi_mac cfl cfh u f4 ) ( __mi_mac cfl cfh v g4 )
        ( __mi_mac cgl cgh q f4 ) ( __mi_mac cgl cgh r g4 )
        : i nf3 # i & cfl M62
        : i ng3 # i & cgl M62
        ( __mi_shr cfl cfh ) ( __mi_shr cgl cgh )
        = f0 nf0 = f1 nf1 = f2 nf2 = f3 nf3 = f4 # i cfl
        = g0 ng0 = g1 ng1 = g2 ng2 = g3 ng3 = g4 # i cgl
        = round + round 1
    }

    // g = 0 and f = ±1 now, d = ±x⁻¹ in (−2m, m): add m if negative,
    // negate with f, carry the limbs back into range, add m again if
    // negative — [0, m).
    : i ca >> d4 63
    = d0 + d0 & m0 ca = d1 + d1 & m1 ca = d2 + d2 & m2 ca = d3 + d3 & m3 ca = d4 + d4 & m4 ca
    : i cn >> f4 63
    = d0 - ^^ d0 cn cn = d1 - ^^ d1 cn cn = d2 - ^^ d2 cn cn = d3 - ^^ d3 cn cn = d4 - ^^ d4 cn cn
    : i L62 4611686018427387903
    = d1 + d1 >> d0 62 = d0 & d0 L62
    = d2 + d2 >> d1 62 = d1 & d1 L62
    = d3 + d3 >> d2 62 = d2 & d2 L62
    = d4 + d4 >> d3 62 = d3 & d3 L62
    : i cb >> d4 63
    = d0 + d0 & m0 cb = d1 + d1 & m1 cb = d2 + d2 & m2 cb = d3 + d3 & m3 cb = d4 + d4 & m4 cb
    = d1 + d1 >> d0 62 = d0 & d0 L62
    = d2 + d2 >> d1 62 = d1 & d1 L62
    = d3 + d3 >> d2 62 = d2 & d2 L62
    = d4 + d4 >> d3 62 = d3 & d3 L62
    // back to four words
    : u64 w0 # u64 d0
    : u64 w1 # u64 d1
    : u64 w2 # u64 d2
    : u64 w3 # u64 d3
    : u64 w4 # u64 d4
    = o0 | w0 << w1 62
    = o1 | >> w1 2 << w2 60
    = o2 | >> w2 4 << w3 58
    = o3 | >> w3 6 << w4 56
}
