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
// request. P-256 computes u1·G + u2·Q as ONE Straus–Shamir pass: the 256
// doublings are shared, and each 4-bit window adds a digit of u1 from an
// affine table of G (built once per process) and a digit of u2 from an
// affine table of Q (built per verify, one batch inversion). Digit 0
// adds nothing.
//
// The scalars come out of r and s, which an attacker chooses, so the
// additions must be right for every relation between the accumulator
// and the entry — equal, negated, either at infinity. Public data lets
// _p256_jmadd_vt simply branch on each case. Nothing here touches BigInt.
// (P-384 keeps its own core below.)

: ~ i g_p256_gtbl 0

// 0, G, 2G, …, 15G as an affine Montgomery table; built on first use and
// shared through publish-once slot 11 (registry: stdlib/std/tls_server.nu).
// G is a public constant, so caching it leaks nothing.
@ __p256_g_tbl → ( Vec i ) {
    ? == g_p256_gtbl 0 {
        : P256Scratch scr ( _p256_scr_new )
        : ( Vec i ) gx ( _p256_to_mont_s scr ( _p256_gx_plain ) )
        : ( Vec i ) gy ( _p256_to_mont_s scr ( _p256_gy_plain ) )
        : ( Vec i ) onem ( _p256_one_mont_s scr )
        : ( Vec i ) tbl ( _p256_affine_multiples scr gx gy onem )
        = g_p256_gtbl ( vec_publish_once [i] 11 tbl )
    } {}
    ^ @ ( Vec i ) { # s g_p256_gtbl }
}

// Nibble `w` (0 = most significant) of a 32-byte big-endian scalar.
@ __p256_nib ( Vec u ) k i w → i {
    : i bv ?? ( vec_get [u] k / w 2 ) { T b → # i b F _ → 0 }
    ^ ? == % w 2 0 & 15 >> bv 4 & 15 bv
}

// Entry `d` of an affine table into (ex, ey).
@ __p256_atbl_at ( Vec i ) ex ( Vec i ) ey ( Vec i ) tbl i d → v {
    : *i tp ( vec_data [i] tbl )
    ( __ec_set4 ex # *i + # i tp * * d 8 8 )
    ( __ec_set4 ey # *i + # i tp * + * d 8 4 8 )
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
    : ( Vec i ) qtbl ( _p256_affine_multiples scr qx qy onem )
    : P256Pt acc ( _p256_pt_mag )
    ( _p256_set_identity_d scr acc )
    : ( Vec i ) ex ( _mag4 )
    : ( Vec i ) ey ( _mag4 )
    : ~ i wi 0
    ~ < wi 64 {
        ? == ( _p256_zmask . acc z ) 0 {
            ( _p256_jdbl_d scr acc ) ( _p256_jdbl_d scr acc )
            ( _p256_jdbl_d scr acc ) ( _p256_jdbl_d scr acc )
        } {}
        : i d1 ( __p256_nib u1 wi )
        ? != d1 0 {
            ( __p256_atbl_at ex ey gtbl d1 )
            ( _p256_jmadd_vt scr acc ex ey onem )
        } {}
        : i d2 ( __p256_nib u2 wi )
        ? != d2 0 {
            ( __p256_atbl_at ex ey qtbl d2 )
            ( _p256_jmadd_vt scr acc ex ey onem )
        } {}
        = wi + wi 1
    }
    ? != ( _p256_zmask . acc z ) 0 { ^ F } {}
    // x(R) = X / Z², compared with r mod n.
    : ( Vec i ) zinv ( _mag4 )
    ( _p256_inv_d scr zinv . acc z )
    ( _p256_sqr_d scr zinv zinv )
    ( _p256_mul_d scr . acc x . acc x zinv )
    ( _p256_from_mont_d scr . acc x . acc x )
    : ( Vec u ) xb ( vec_with_cap [u] 32 )
    ( _p256_limbs_to_be xb . acc x )
    ^ ( bytes_eq ( p256n_reduce_be xb ) rb )
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
