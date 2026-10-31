// stdlib/std/ecdsa_p256.nu — pure-NURL ECDSA on the NIST P-256
// (secp256r1) and P-384 (secp384r1) curves. No OpenSSL.
//
//   ( ecdsa_p256_verify point r s hash ) → b
//   ( ecdsa_p384_verify point r s hash ) → b
//   ( ecdsa_p256_sign priv hash )       → ( Vec u )
//
// point = uncompressed public key (0x04 || X || Y, 65 / 97 bytes).
// r, s   = signature integers (big-endian bytes).
// hash   = the message digest; a digest longer than the curve is
//          truncated to its leftmost bits per FIPS 186-5 §6.4.1.
//
// The SECRET paths (signing nonce, ECDH) run on the constant-time
// fixed-limb Montgomery field (std/p256_field); verification — public
// data, one per certificate in a TLS chain, one per JWT-authenticated
// request — runs on the same fixed-limb fields variable-time-free of
// BigInt (P-384 core: std/p384_field). BigInt remains for parsing and
// the cheap validation arithmetic only.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bigint.nu`
$ `stdlib/std/hash_sha256.nu`  // prepared HMAC keys for the RFC 6979 nonce
$ `stdlib/std/p256_field.nu`  // fully constant-time scalar mult (secret path)
$ `stdlib/std/p256_scalar.nu`  // fixed-width GF(n) for the signing scalar arithmetic
$ `stdlib/std/p384_field.nu`  // fixed-width P-384 verify core (public path)

// ── curve constants (hex → BigInt) ────────────────────────────────
@ __hx s h → BigInt {
    : ( Vec u ) v ?? ( bytes_from_hex h ) { T x → x F _ → ( vec_new [u] ) }
    : BigInt r ( bigint_from_bytes_be v )
    ^ r
}

@ __p384_p → BigInt { ^ ( __hx `fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff` ) }

@ __p384_n → BigInt { ^ ( __hx `ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973` ) }

@ __p384_b → BigInt { ^ ( __hx `b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef` ) }

// ── field arithmetic mod p ────────────────────────────────────────
@ __fmul BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_mul a b )
    : BigInt r ( bigint_rem t p )
    ^ r
}

@ __fadd BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_add a b )
    : BigInt r ( bigint_rem t p )
    ^ r
}

@ __fsub BigInt a BigInt b BigInt p → BigInt {
    : BigInt t1 ( bigint_add a p )
    : BigInt t2 ( bigint_sub t1 b )
    : BigInt r ( bigint_rem t2 p )
    ^ r
}

@ __fsqr BigInt a BigInt p → BigInt { ^ ( __fmul a a p ) }

// On-curve + in-field validation of an affine point (M3): 0 ≤ x,y < p,
// (x,y) ≠ O, and y² ≡ x³ − 3x + b (mod p). P-256/P-384 have cofactor 1, so
// this is a full subgroup membership check.
@ __on_curve BigInt x BigInt y BigInt p BigInt b → b {
    : BigInt zero ( bigint_zero )
    : ~ b ok T
    ? >= ( bigint_cmp x p ) 0 { = ok F } {}
    ? >= ( bigint_cmp y p ) 0 { = ok F } {}
    ? < ( bigint_cmp x zero ) 0 { = ok F } {}
    ? < ( bigint_cmp y zero ) 0 { = ok F } {}
    ? & ( bigint_is_zero x ) ( bigint_is_zero y ) { = ok F } {}
    ? ok {
        : BigInt x2 ( __fsqr x p )
        : BigInt x3 ( __fmul x2 x p )
        : BigInt three ( bigint_from_i 3 )
        : BigInt tx ( __fmul three x p )
        : BigInt rhs0 ( __fsub x3 tx p )
        : BigInt rhs ( __fadd rhs0 b p )
        : BigInt lhs ( __fsqr y p )
        = ok == ( bigint_cmp lhs rhs ) 0
    } {}
    ^ ok
}

// ── public points ─────────────────────────────────────────────────
// A peer's ECDH share and a verifier's public key arrive as the
// uncompressed SEC1 encoding 0x04 ‖ X(32) ‖ Y(32). Both are decoded and
// validated on the fixed-width field — canonical coordinates (x, y < p)
// and the curve equation (M3: an off-curve point would let a peer pull
// our scalar out through an invalid-curve attack). P-256's cofactor is 1,
// so an on-curve point other than ∞ (which has no affine encoding) has
// order n.

// Four limbs at `src` into `dst`.
@ __ec_set4 ( Vec i ) dst * i src → v {
    : *i dp ( vec_data [i] dst )
    = . dp 0 . src 0 = . dp 1 . src 1 = . dp 2 . src 2 = . dp 3 . src 3
}

// Decode and validate into plain limbs (xl, yl); F if the encoding is not
// a point of the curve.
@ __p256_decode_point ( Vec u ) pt ( Vec i ) xl ( Vec i ) yl → b {
    ? != ( vec_len [u] pt ) 65 { ^ F } {}
    ? != ?? ( vec_get [u] pt 0 ) { T x → # i x F _ → 0 } 4 { ^ F } {}
    ( __ec_set4 xl ( vec_data [i] ( _p256_be32_to_limbs pt 1 ) ) )
    ( __ec_set4 yl ( vec_data [i] ( _p256_be32_to_limbs pt 33 ) ) )
    ? ! & ( _p256_lt_p xl ) ( _p256_lt_p yl ) { ^ F } {}
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) xm ( _p256_to_mont_s scr xl )
    : ( Vec i ) ym ( _p256_to_mont_s scr yl )
    ^ ( _p256_on_curve scr xm ym )
}

// ── ECDHE over NIST P-256 (secp256r1) ─────────────────────────────
// The TLS 1.3 secp256r1 group (RFC 8446 §4.2.8.2 / RFC 8422): the
// public key is an uncompressed point 0x04 || X(32) || Y(32), and the
// shared secret is the 32-byte big-endian X of scalar·peer. `scalar` is
// the 32-byte ephemeral private key.

// Private scalar → 65-byte uncompressed public point.
@ p256_ecdh_keygen ( Vec u ) scalar → ( Vec u ) {
    // scalar·G — fixed-base comb (G is the generator).
    : ( Vec u ) xy ( p256ct_scalarmult_base scalar )
    : ( Vec u ) out ( vec_with_cap [u] 65 )
    ( vec_push [u] out # u 4 )
    ( bytes_extend_bytes out xy )
    ^ out
}

// scalar · peer-point → 32-byte shared X. Returns [] on a malformed or
// off-curve peer point. The multiply is p256ct_scalarmult: constant-time
// in the scalar and complete for every scalar.
@ p256_ecdh_shared ( Vec u ) scalar ( Vec u ) peer → ( Vec u ) {
    : ( Vec i ) xl ( _mag4 )
    : ( Vec i ) yl ( _mag4 )
    ? ! ( __p256_decode_point peer xl yl ) { ^ ( vec_new [u] ) } {}
    : ( Vec u ) xy ( p256ct_scalarmult scalar xl yl )
    ^ ( bytes_slice xy 0 32 )
}

// ── verify ────────────────────────────────────────────────────────
// Signature verification runs entirely over PUBLIC data (a certificate's
// key, the signature's r/s, a message digest), so it needs no
// operand-independent timing — it needs speed, because a TLS client pays
// one verify per certificate in the chain and a JWT server one per
// request. P-256 computes u1·G + u2·Q as ONE interleaved pass over the
// two scalars' width-w NAFs: the 256 doublings are shared, and a non-zero
// digit adds ± an odd multiple of its point from an affine table. A NAF
// of width w has a non-zero digit about once every w + 1 positions, so
// G's digits (width 7, a table of 1·G … 127·G built once per process) cost
// about 32 additions and Q's (width 5, 1·Q … 15·Q built per verify with
// one batch inversion) about 43 — against about 120 for the 4-bit windows
// this replaces, whose fifteen-in-sixteen digits were non-zero.
//
// The scalars come out of r and s, which an attacker chooses, so the
// additions must be right for every relation between the accumulator
// and the entry — equal, negated, either at infinity. Public data lets
// _p256_jmadd_vt simply branch on each case. Nothing here touches BigInt.
// (P-384 keeps its own core below.)

: ~ i g_p256_gtbl 0

// The affine odd multiples 1·P, 3·P, …, (2k − 1)·P of a Montgomery affine
// point P of order n, entry j at [8j, 8j + 8) as x‖y: P, 2P by one
// doubling, then (2j + 1)·P = (2j − 1)·P + 2P by Jacobian additions — never
// ±2P or ∞ for k ≤ 64, since 2j − 1 ≢ ±2 (mod n) — and ONE batch
// inversion for all of them. P is public in every use.
// requires: px, py and onem hold 4 limbs; 1 ≤ k ≤ 64.
@ __p256_odd_tbl P256Scratch scr ( Vec i ) px ( Vec i ) py ( Vec i ) onem i k → ( Vec i ) {
    : ( Vec i ) jac ( _magn * k 12 )
    : P256Pt p ( _p256_pt_mag )
    : P256Pt d ( _p256_pt_mag )
    ( __ec_set4 . p x ( vec_data [i] px ) ) ( __ec_set4 . p y ( vec_data [i] py ) ) ( __ec_set4 . p z ( vec_data [i] onem ) )
    ( __ec_set4 . d x ( vec_data [i] px ) ) ( __ec_set4 . d y ( vec_data [i] py ) ) ( __ec_set4 . d z ( vec_data [i] onem ) )
    ( _p256_tbl_put jac 0 p )
    ( _p256_jdbl_d scr d )
    : ~ i j 1
    ~ < j k {
        ( _p256_jadd_d scr p d )
        ( _p256_tbl_put jac j p )
        = j + j 1
    }
    : ( Vec i ) tbl ( _magn * k 8 )
    ( _p256_batch_affine scr jac k tbl 0 onem )
    ^ tbl
}

// 1·G, 3·G, …, 127·G (64 entries) as an affine Montgomery table; built on
// first use and shared through publish-once slot 11 (registry:
// stdlib/std/tls_server.nu). G is a public constant, so caching it leaks
// nothing.
@ __p256_g_tbl → ( Vec i ) {
    ? == g_p256_gtbl 0 {
        : P256Scratch scr ( _p256_scr_new )
        : ( Vec i ) gx ( _p256_to_mont_s scr ( _p256_gx_plain ) )
        : ( Vec i ) gy ( _p256_to_mont_s scr ( _p256_gy_plain ) )
        : ( Vec i ) onem ( _p256_one_mont_s scr )
        : ( Vec i ) tbl ( __p256_odd_tbl scr gx gy onem 64 )
        = g_p256_gtbl ( vec_publish_once [i] 11 tbl )
    } {}
    ^ @ ( Vec i ) { # s g_p256_gtbl }
}

// The width-w NAF of a 32-byte big-endian scalar: 257 digits, digit i the
// coefficient of 2^i, each 0 or odd with |d| < 2^(w−1), and no two
// non-zero digits within w positions of each other. Variable time: for
// public scalars only (verify's u1 and u2).
@ __p256_wnaf ( Vec u ) k i w → ( Vec i ) {
    : ( Vec i ) d ( vec_zeroed [i] 257 )
    : *i dp ( vec_data [i] d )
    : ( Vec i ) kl ( _p256_be32_to_limbs k 0 )
    : *i kp ( vec_data [i] kl )
    : ~ u64 l0 # u64 . kp 0
    : ~ u64 l1 # u64 . kp 1
    : ~ u64 l2 # u64 . kp 2
    : ~ u64 l3 # u64 . kp 3
    : ~ u64 l4 0
    : i full << 1 w
    : i half << 1 - w 1
    : ~ i at 0
    ~ & < at 257 != 0 | | | | l0 l1 l2 l3 l4 {
        ? != 0 & l0 1 {
            : ~ i dd # i & l0 # u64 - full 1
            ? >= dd half { = dd - dd full } {}
            = . dp at dd
            // k −= dd: dd > 0 borrows up, dd < 0 carries up
            ? > dd 0 {
                : u64 s # u64 dd
                : ~ u64 bb ( nurl_subb_hi l0 s 0 )
                = l0 ( nurl_subb_lo l0 s 0 )
                : u64 n1 ( nurl_subb_lo l1 0 bb )
                = bb ( nurl_subb_hi l1 0 bb )
                = l1 n1
                : u64 n2 ( nurl_subb_lo l2 0 bb )
                = bb ( nurl_subb_hi l2 0 bb )
                = l2 n2
                : u64 n3 ( nurl_subb_lo l3 0 bb )
                = bb ( nurl_subb_hi l3 0 bb )
                = l3 n3
                = l4 ( nurl_subb_lo l4 0 bb )
            } {
                : u64 s # u64 - 0 dd
                : ~ u64 cc ( nurl_addc_hi l0 s 0 )
                = l0 ( nurl_addc_lo l0 s 0 )
                : u64 n1 ( nurl_addc_lo l1 0 cc )
                = cc ( nurl_addc_hi l1 0 cc )
                = l1 n1
                : u64 n2 ( nurl_addc_lo l2 0 cc )
                = cc ( nurl_addc_hi l2 0 cc )
                = l2 n2
                : u64 n3 ( nurl_addc_lo l3 0 cc )
                = cc ( nurl_addc_hi l3 0 cc )
                = l3 n3
                = l4 ( nurl_addc_lo l4 0 cc )
            }
        } {}
        // k >>= 1
        = l0 | >> l0 1 << l1 63
        = l1 | >> l1 1 << l2 63
        = l2 | >> l2 1 << l3 63
        = l3 | >> l3 1 << l4 63
        = l4 >> l4 1
        = at + at 1
    }
    ^ d
}

// Entry `d` of an affine table into (ex, ey).
@ __p256_atbl_at ( Vec i ) ex ( Vec i ) ey ( Vec i ) tbl i d → v {
    : *i tp ( vec_data [i] tbl )
    ( __ec_set4 ex # *i + # i tp * * d 8 8 )
    ( __ec_set4 ey # *i + # i tp * + * d 8 4 8 )
}

// y ← p − y, for a y in [1, p − 1] (a point of P-256 never has y = 0:
// the group has odd order, so no point is its own negation).
@ __ec_negy ( Vec i ) y → v {
    : *i yp ( vec_data [i] y )
    : u64 d0 ( nurl_subb_lo 0xffffffffffffffff # u64 . yp 0 0 )
    : ~ u64 bb ( nurl_subb_hi 0xffffffffffffffff # u64 . yp 0 0 )
    : u64 d1 ( nurl_subb_lo 0x00000000ffffffff # u64 . yp 1 bb )
    = bb ( nurl_subb_hi 0x00000000ffffffff # u64 . yp 1 bb )
    : u64 d2 ( nurl_subb_lo 0 # u64 . yp 2 bb )
    = bb ( nurl_subb_hi 0 # u64 . yp 2 bb )
    : u64 d3 ( nurl_subb_lo 0xffffffff00000001 # u64 . yp 3 bb )
    = . yp 0 # i d0 = . yp 1 # i d1 = . yp 2 # i d2 = . yp 3 # i d3
}

// acc += digit · (odd-multiple table), for a non-zero NAF digit: entry
// (|digit| − 1)/2, its y negated for a negative digit.
@ __p256_wnaf_add P256Scratch scr P256Pt acc ( Vec i ) tbl i digit ( Vec i ) ex ( Vec i ) ey ( Vec i ) onem → v {
    : i mag ? < digit 0 - 0 digit digit
    ( __p256_atbl_at ex ey tbl >> - mag 1 1 )
    ? < digit 0 { ( __ec_negy ey ) } {}
    ( _p256_jmadd_vt scr acc ex ey onem )
}

// The P-256 verify core: u1 = z·s⁻¹, u2 = r·s⁻¹ over GF(n), R = u1·G +
// u2·Q, accept iff R ≠ ∞ and x(R) ≡ r (mod n). zb, rb, sb are 32-byte
// big-endian with r, s already in [1, n−1]; (qxl, qyl) is a validated
// public key, plain limbs.
@ __p256_verify_core ( Vec u ) zb ( Vec u ) rb ( Vec u ) sb ( Vec i ) qxl ( Vec i ) qyl → b {
    : ( Vec u ) w ( p256n_inv_be sb )
    : ( Vec u ) u1 ( p256n_mulmod_be zb w )
    : ( Vec u ) u2 ( p256n_mulmod_be rb w )
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) onem ( _p256_one_mont_s scr )
    : ( Vec i ) gtbl ( __p256_g_tbl )
    : ( Vec i ) qx ( _p256_to_mont_s scr qxl )
    : ( Vec i ) qy ( _p256_to_mont_s scr qyl )
    : ( Vec i ) qtbl ( __p256_odd_tbl scr qx qy onem 8 )
    : ( Vec i ) dg ( __p256_wnaf u1 7 )
    : ( Vec i ) dq ( __p256_wnaf u2 5 )
    : *i gp ( vec_data [i] dg )
    : *i qp ( vec_data [i] dq )
    : P256Pt acc ( _p256_pt_mag )
    ( _p256_set_identity_d scr acc )
    : ( Vec i ) ex ( _mag4 )
    : ( Vec i ) ey ( _mag4 )
    // from the highest non-zero digit down; doublings of ∞ are skipped
    : ~ i at 256
    ~ & >= at 0 == 0 | . gp at . qp at { = at - at 1 }
    ~ >= at 0 {
        ? == ( _p256_zmask . acc z ) 0 { ( _p256_jdbl_d scr acc ) } {}
        : i a . gp at
        ? != a 0 { ( __p256_wnaf_add scr acc gtbl a ex ey onem ) } {}
        : i b . qp at
        ? != b 0 { ( __p256_wnaf_add scr acc qtbl b ex ey onem ) } {}
        = at - at 1
    }
    ? != ( _p256_zmask . acc z ) 0 { ^ F } {}
    // x(R) = X/Z² ≡ r (mod n) ⇔ X = r'·Z² for r' = r or, when r + n < p,
    // r' = r + n (x(R) < p < 2n): compared in the field, so no inversion.
    : ( Vec i ) z2 ( _mag4 )
    ( _p256_sqr_d scr z2 . acc z )
    : ( Vec i ) rl ( _p256_be32_to_limbs rb 0 )
    : ( Vec i ) rm ( _p256_to_mont_s scr rl )
    : ( Vec i ) t ( _mag4 )
    ( _p256_mul_d scr t rm z2 )
    ? ( _p256_eq t . acc x ) { ^ T } {}
    // r + n, plain limbs (r < n, so it fits 256 bits only when small)
    : *i rp ( vec_data [i] rl )
    : u64 s0 ( nurl_addc_lo # u64 . rp 0 0xf3b9cac2fc632551 0 )
    : ~ u64 cc ( nurl_addc_hi # u64 . rp 0 0xf3b9cac2fc632551 0 )
    : u64 s1 ( nurl_addc_lo # u64 . rp 1 0xbce6faada7179e84 cc )
    = cc ( nurl_addc_hi # u64 . rp 1 0xbce6faada7179e84 cc )
    : u64 s2 ( nurl_addc_lo # u64 . rp 2 0xffffffffffffffff cc )
    = cc ( nurl_addc_hi # u64 . rp 2 0xffffffffffffffff cc )
    : u64 s3 ( nurl_addc_lo # u64 . rp 3 0xffffffff00000000 cc )
    = cc ( nurl_addc_hi # u64 . rp 3 0xffffffff00000000 cc )
    ? != cc 0 { ^ F } {}
    = . rp 0 # i s0 = . rp 1 # i s1 = . rp 2 # i s2 = . rp 3 # i s3
    ? ! ( _p256_lt_p rl ) { ^ F } {}
    : ( Vec i ) rm2 ( _p256_to_mont_s scr rl )
    ( _p256_mul_d scr t rm2 z2 )
    ^ ( _p256_eq t . acc x )
}

// A DER-decoded integer (big-endian, any leading zeros) as exactly 32
// bytes; [] when its value needs more.
@ __p256_fixed32 ( Vec u ) v → ( Vec u ) {
    : i n ( vec_len [u] v )
    : ~ i lead 0
    ~ & < lead n == ?? ( vec_get [u] v lead ) { T x → # i x F _ → 1 } 0 { = lead + lead 1 }
    : i sig - n lead
    ? > sig 32 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) out ( vec_zeroed [u] - 32 sig )
    ( bytes_extend_bytes out ( bytes_slice v lead n ) )
    ^ out
}

@ ecdsa_p256_verify ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    : ( Vec i ) qxl ( _mag4 )
    : ( Vec i ) qyl ( _mag4 )
    ? ! ( __p256_decode_point point qxl qyl ) { ^ F } {}
    : ( Vec u ) rb ( __p256_fixed32 r )
    : ( Vec u ) sb ( __p256_fixed32 s )
    ? | == ( vec_len [u] rb ) 0 == ( vec_len [u] sb ) 0 { ^ F } {}
    // r, s ∈ [1, n−1]
    ? ! & ( p256n_in_range_be rb ) ( p256n_in_range_be sb ) { ^ F } {}
    // z = the LEFTMOST 32 bytes of the digest (FIPS 186-5 §6.4.1: a longer
    // digest is truncated to the order's bit length, not reduced), a
    // shorter one left-padded.
    : i hlen ( vec_len [u] hash )
    : i m ? < hlen 32 hlen 32
    : ( Vec u ) zb ( vec_zeroed [u] - 32 m )
    ( bytes_extend_bytes zb ( bytes_slice hash 0 m ) )
    ^ ( __p256_verify_core zb rb sb qxl qyl )
}

// P-384's verifier: BigInt parsing, range checks and on-curve validation
// (a = -3, as for P-256), then std/p384_field's double-scalar core. It
// takes the curve constants and the coordinate byte length, and consumes
// p / nn / cb.
@ __ecdsa_verify BigInt p BigInt nn BigInt cb i clen ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ? != ( vec_len [u] point ) + 1 * 2 clen {
        ^ F
    } {}
    ? != ?? ( vec_get [u] point 0 ) { T x → # i x F _ → 0 } 4 {
        ^ F
    } {}

    : ( Vec u ) qxb ( bytes_slice point 1 + 1 clen )
    : ( Vec u ) qyb ( bytes_slice point + 1 clen + 1 * 2 clen )
    : BigInt qx ( bigint_from_bytes_be qxb )
    : BigInt qy ( bigint_from_bytes_be qyb )
    // M3: reject a public key that is off-curve or out of field range.
    ? ! ( __on_curve qx qy p cb ) {
        ^ F
    } {}

    : BigInt br ( bigint_from_bytes_be r )
    : BigInt bs ( bigint_from_bytes_be s )
    : BigInt one ( bigint_from_i 1 )

    : ~ b ok T
    // r,s must be in [1, n-1]
    ? < ( bigint_cmp br one ) 0 { = ok F } {}
    ? < ( bigint_cmp bs one ) 0 { = ok F } {}
    ? >= ( bigint_cmp br nn ) 0 { = ok F } {}
    ? >= ( bigint_cmp bs nn ) 0 { = ok F } {}

    : ~ b result F
    ? ok {
        // z = the LEFTMOST clen bytes of the digest (FIPS 186-5 §6.4.1:
        // a digest longer than the group order is truncated to its
        // leftmost qlen bits — NOT reduced as a full-width integer,
        // which accepts a different value whenever the digest is longer
        // than the curve, e.g. SHA-384 with P-256). A shorter digest is
        // left-padded: same integer, fixed width.
        : i hlen ( vec_len [u] hash )
        : i m ? < hlen clen hlen clen
        : ( Vec u ) zb ( vec_with_cap [u] clen )
        : ~ i k m
        ~ < k clen { ( vec_push [u] zb # u 0 ) = k + k 1 }
        : ~ i j 0
        ~ < j m {
            ( vec_push [u] zb ?? ( vec_get [u] hash j ) { T x → x F _ → # u 0 } )
            = j + j 1
        }
        : ( Vec u ) rb ( bigint_to_bytes_be br clen )
        : ( Vec u ) sb ( bigint_to_bytes_be bs clen )
        = result ( p384_ecdsa_verify_core zb rb sb qxb qyb )
    } {}
    ^ result
}

@ ecdsa_p384_verify ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ^ ( __ecdsa_verify ( __p384_p ) ( __p384_n ) ( __p384_b ) 48 point r s hash )
}

// ── ECDSA P-256 signing (RFC 6979 deterministic nonce) ──────────────
//
// `ecdsa_p256_sign priv hash` → 64-byte raw signature r‖s (each 32 B BE).
//   priv = 32-byte big-endian private scalar.
//   hash = the message digest (SHA-256 → 32 bytes).
// The nonce k is generated deterministically per RFC 6979 (HMAC-SHA-256),
// so signing needs no RNG and can never reuse a nonce — and the output is
// reproducible, hence KAT-testable. Verify with `ecdsa_p256_verify`.

@ __ec_bytes_fill i val i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u val ) = k + k 1 }
    ^ v
}

// True iff all 32 bytes are zero (an r or s of 0 must be retried). OR-fold
// so the scan is data-independent, like the rest of the signing path.
@ __ec_zero32 ( Vec u ) v → b {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 32 { = acc | acc ?? ( vec_get [u] v k ) { T x → # i x F _ → 0 } = k + k 1 }
    ^ == acc 0
}

// `v` as exactly 32 big-endian bytes: its LEFTMOST 32 when longer (a
// digest's bits2int, FIPS 186-5 §6.4.1 / RFC 6979 §2.3.2 — the same
// truncation verify applies), left zero-padded when shorter.
@ __ec_be32 ( Vec u ) v → ( Vec u ) {
    : i n ( vec_len [u] v )
    : ( Vec u ) o ( vec_zeroed [u] 32 )
    : i m ? < n 32 n 32
    ? > m 0 { ( nurl_memcpy # s + # i ( vec_data [u] o ) - 32 m # s ( vec_data [u] v ) m ) } {}
    ^ o
}

// V ‖ sep ‖ priv32 ‖ b2o32  (the RFC 6979 HMAC input blocks)
@ __ec_hmac_msg ( Vec u ) V i sep ( Vec u ) priv32 ( Vec u ) b2o → ( Vec u ) {
    : ( Vec u ) m ( vec_with_cap [u] 97 )
    ( bytes_extend_bytes m V )
    ( vec_push [u] m # u sep )
    ( bytes_extend_bytes m priv32 )
    ( bytes_extend_bytes m b2o )
    ^ m
}

// Every scalar stays a fixed 32 bytes on the fixed-width GF(n) field
// (stdlib/std/p256_scalar.nu) — no variable-length integer, no heap
// magnitude per step — and each HMAC key of RFC 6979 is prepared once
// (hmac_sha256_key) for the MACs made under it.
@ ecdsa_p256_sign ( Vec u ) priv ( Vec u ) hash → ( Vec u ) {
    : ( Vec u ) priv32 ( __ec_be32 priv )
    // z = bits2int(hash), and b2o = int2octets(z mod n): z < 2^256 < 2n,
    // so one conditional subtraction reduces it.
    : ( Vec u ) z32 ( __ec_be32 hash )
    : ( Vec u ) b2o ( p256n_reduce_be z32 )

    // RFC 6979 §3.2 steps b–g: V = 0x01.., K = 0x00.., two HMAC mixes.
    : ~ ( Vec u ) V ( __ec_bytes_fill 1 32 )
    : ( Vec u ) k0 ( __ec_bytes_fill 0 32 )
    : HmacSha256 h0 ( hmac_sha256_key k0 )
    : ( Vec u ) k1 ( hmac_sha256_mac h0 ( __ec_hmac_msg V 0 priv32 b2o ) )
    : HmacSha256 h1 ( hmac_sha256_key k1 )
    = V ( hmac_sha256_mac h1 V )
    : ( Vec u ) k2 ( hmac_sha256_mac h1 ( __ec_hmac_msg V 1 priv32 b2o ) )
    : ~ HmacSha256 hk ( hmac_sha256_key k2 )
    = V ( hmac_sha256_mac hk V )

    : ~ ( Vec u ) sig ( vec_new [u] )
    : ~ b done F
    ~ ! done {
        // T = HMAC(K, V); qlen == hlen == 256 so one block IS the candidate.
        = V ( hmac_sha256_mac hk V )
        ? ( p256n_in_range_be V ) {
            // k·G — fixed-base comb (G is the generator), constant-time.
            : ( Vec u ) Rxy ( p256ct_scalarmult_base V )
            : ( Vec u ) Rxb ( bytes_slice Rxy 0 32 )
            // r = R.x mod n; s = k⁻¹·(z + r·d) mod n.
            : ( Vec u ) r ( p256n_reduce_be Rxb )
            // identity result → X = 0 → r ≡ 0, retried below (no inf branch).
            ? ! ( __ec_zero32 r ) {
                : ( Vec u ) kinv ( p256n_inv_be V )
                : ( Vec u ) rd ( p256n_mulmod_be r priv32 )
                : ( Vec u ) zrd ( p256n_addmod_be b2o rd )
                : ( Vec u ) s ( p256n_mulmod_be kinv zrd )
                ? ! ( __ec_zero32 s ) {
                    ( bytes_extend_bytes sig r ) ( bytes_extend_bytes sig s )
                    = done T
                } {}
            } {}
        } {}
        ? ! done {
            // K = HMAC(K, V‖0x00); V = HMAC(K, V) — advance the generator.
            : ( Vec u ) mz ( vec_with_cap [u] 33 )
            ( bytes_extend_bytes mz V )
            ( vec_push [u] mz # u 0 )
            : ( Vec u ) kn ( hmac_sha256_mac hk mz )
            = hk ( hmac_sha256_key kn )
            = V ( hmac_sha256_mac hk V )
        } {}
    }

    ^ sig
}
