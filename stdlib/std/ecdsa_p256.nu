// stdlib/std/ecdsa_p256.nu — pure-NURL ECDSA verification on the NIST
// P-256 (secp256r1) curve. No OpenSSL. Built on BigInt; points are held
// in Jacobian coordinates so the double-and-add ladder needs only one
// field inversion at the very end.
//
//   ( ecdsa_p256_verify point r s hash ) → b
//
// point = 65-byte uncompressed public key (0x04 || X || Y).
// r, s   = signature integers (big-endian bytes).
// hash   = the message digest (SHA-256 → 32 bytes).

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bigint.nu`

// ── curve constants (hex → BigInt) ────────────────────────────────
@ __hx s h → BigInt {
    : ( Vec u ) v ?? ( bytes_from_hex h ) { T x → x F _ → ( vec_new [u] ) }
    : BigInt r ( bigint_from_bytes_be v )
    ( vec_free [u] v )
    ^ r
}

@ __p256_p → BigInt { ^ ( __hx `ffffffff00000001000000000000000000000000ffffffffffffffffffffffff` ) }

@ __p256_n → BigInt { ^ ( __hx `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551` ) }

@ __p256_gx → BigInt { ^ ( __hx `6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296` ) }

@ __p256_gy → BigInt { ^ ( __hx `4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5` ) }

@ __p384_p → BigInt { ^ ( __hx `fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff` ) }

@ __p384_n → BigInt { ^ ( __hx `ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973` ) }

@ __p384_gx → BigInt { ^ ( __hx `aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7` ) }

@ __p384_gy → BigInt { ^ ( __hx `3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f` ) }

// ── field arithmetic mod p ────────────────────────────────────────
@ __fmul BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_mul a b )
    : BigInt r ( bigint_rem t p )
    ( bigint_free t )
    ^ r
}

@ __fadd BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_add a b )
    : BigInt r ( bigint_rem t p )
    ( bigint_free t )
    ^ r
}

@ __fsub BigInt a BigInt b BigInt p → BigInt {
    : BigInt t1 ( bigint_add a p )
    : BigInt t2 ( bigint_sub t1 b )
    : BigInt r ( bigint_rem t2 p )
    ( bigint_free t1 )
    ( bigint_free t2 )
    ^ r
}

@ __fsqr BigInt a BigInt p → BigInt { ^ ( __fmul a a p ) }

@ __f2 BigInt a BigInt p → BigInt { ^ ( __fadd a a p ) }

@ __f3 BigInt a BigInt p → BigInt {
    : BigInt d ( __f2 a p )
    : BigInt r ( __fadd d a p )
    ( bigint_free d )
    ^ r
}

@ __f4 BigInt a BigInt p → BigInt {
    : BigInt d ( __f2 a p )
    : BigInt r ( __f2 d p )
    ( bigint_free d )
    ^ r
}

@ __f8 BigInt a BigInt p → BigInt {
    : BigInt d ( __f4 a p )
    : BigInt r ( __f2 d p )
    ( bigint_free d )
    ^ r
}
// a^(p-2) mod p — multiplicative inverse.
@ __finv BigInt a BigInt p → BigInt {
    : BigInt two ( bigint_from_i 2 )
    : BigInt pm2 ( bigint_sub p two )
    : BigInt r ( bigint_modpow a pm2 p )
    ( bigint_free two )
    ( bigint_free pm2 )
    ^ r
}

// ── Jacobian point ────────────────────────────────────────────────
: Jac { BigInt x BigInt y BigInt z b inf }

@ __jinf → Jac {
    ^ @ Jac { ( bigint_from_i 1 ) ( bigint_from_i 1 ) ( bigint_from_i 0 ) T }
}

@ __jfree Jac q → v {
    ( bigint_free . q x )
    ( bigint_free . q y )
    ( bigint_free . q z )
}

@ __jclone Jac q → Jac {
    ^ @ Jac { ( bigint_clone . q x ) ( bigint_clone . q y ) ( bigint_clone . q z ) . q inf }
}

// Point doubling (a = -3 form).
@ __jdouble Jac q BigInt p → Jac {
    ? . q inf { ^ ( __jclone q ) } {}
    ? ( bigint_is_zero . q y ) { ^ ( __jinf ) } {}
    : BigInt A ( __fsqr . q y p )
    : BigInt xa ( __fmul . q x A p )
    : BigInt B ( __f4 xa p )
    : BigInt a2 ( __fsqr A p )
    : BigInt C ( __f8 a2 p )
    : BigInt zsq ( __fsqr . q z p )
    : BigInt xm ( __fsub . q x zsq p )
    : BigInt xp ( __fadd . q x zsq p )
    : BigInt dm ( __fmul xm xp p )
    : BigInt D ( __f3 dm p )
    : BigInt dsq ( __fsqr D p )
    : BigInt b2 ( __f2 B p )
    : BigInt X3 ( __fsub dsq b2 p )
    : BigInt bx ( __fsub B X3 p )
    : BigInt dbx ( __fmul D bx p )
    : BigInt Y3 ( __fsub dbx C p )
    : BigInt yz ( __fmul . q y . q z p )
    : BigInt Z3 ( __f2 yz p )
    ( bigint_free A ) ( bigint_free xa ) ( bigint_free B ) ( bigint_free a2 )
    ( bigint_free C ) ( bigint_free zsq ) ( bigint_free xm ) ( bigint_free xp )
    ( bigint_free dm ) ( bigint_free D ) ( bigint_free dsq ) ( bigint_free b2 )
    ( bigint_free bx ) ( bigint_free dbx ) ( bigint_free yz )
    ^ @ Jac { X3 Y3 Z3 F }
}

// Point addition (general Jacobian + Jacobian).
@ __jadd Jac p1 Jac p2 BigInt p → Jac {
    ? . p1 inf { ^ ( __jclone p2 ) } {}
    ? . p2 inf { ^ ( __jclone p1 ) } {}
    : BigInt z1sq ( __fsqr . p1 z p )
    : BigInt z2sq ( __fsqr . p2 z p )
    : BigInt u1 ( __fmul . p1 x z2sq p )
    : BigInt u2 ( __fmul . p2 x z1sq p )
    : BigInt z2cu ( __fmul . p2 z z2sq p )
    : BigInt z1cu ( __fmul . p1 z z1sq p )
    : BigInt s1 ( __fmul . p1 y z2cu p )
    : BigInt s2 ( __fmul . p2 y z1cu p )
    : i ucmp ( bigint_cmp u1 u2 )
    : i scmp ( bigint_cmp s1 s2 )
    ? == ucmp 0 {
        ( bigint_free z1sq ) ( bigint_free z2sq ) ( bigint_free u1 ) ( bigint_free u2 )
        ( bigint_free z2cu ) ( bigint_free z1cu ) ( bigint_free s1 ) ( bigint_free s2 )
        ? == scmp 0 { ^ ( __jdouble p1 p ) } { ^ ( __jinf ) }
    } {}
    : BigInt H ( __fsub u2 u1 p )
    : BigInt R ( __fsub s2 s1 p )
    : BigInt hsq ( __fsqr H p )
    : BigInt hcu ( __fmul H hsq p )
    : BigInt u1hsq ( __fmul u1 hsq p )
    : BigInt rsq ( __fsqr R p )
    : BigInt t1 ( __fsub rsq hcu p )
    : BigInt u1hsq2 ( __f2 u1hsq p )
    : BigInt X3 ( __fsub t1 u1hsq2 p )
    : BigInt t2 ( __fsub u1hsq X3 p )
    : BigInt rt2 ( __fmul R t2 p )
    : BigInt s1hcu ( __fmul s1 hcu p )
    : BigInt Y3 ( __fsub rt2 s1hcu p )
    : BigInt z1z2 ( __fmul . p1 z . p2 z p )
    : BigInt Z3 ( __fmul H z1z2 p )
    ( bigint_free z1sq ) ( bigint_free z2sq ) ( bigint_free u1 ) ( bigint_free u2 )
    ( bigint_free z2cu ) ( bigint_free z1cu ) ( bigint_free s1 ) ( bigint_free s2 )
    ( bigint_free H ) ( bigint_free R ) ( bigint_free hsq ) ( bigint_free hcu )
    ( bigint_free u1hsq ) ( bigint_free rsq ) ( bigint_free t1 ) ( bigint_free u1hsq2 )
    ( bigint_free t2 ) ( bigint_free rt2 ) ( bigint_free s1hcu ) ( bigint_free z1z2 )
    ^ @ Jac { X3 Y3 Z3 F }
}

// k · P over the bits of k (big-endian byte view), MSB to LSB.
@ __jmul ( Vec u ) k Jac base BigInt p → Jac {
    : ~ Jac acc ( __jinf )
    : i n ( vec_len [u] k )
    : ~ i bi 0
    ~ < bi n {
        : i byte ?? ( vec_get [u] k bi ) { T x → # i x F _ → 0 }
        : ~ i bit 7
        ~ >= bit 0 {
            : Jac d ( __jdouble acc p )
            ( __jfree acc )
            = acc d
            ? != 0 & >> byte bit 1 {
                : Jac a ( __jadd acc base p )
                ( __jfree acc )
                = acc a
            } {}
            = bit - bit 1
        }
        = bi + bi 1
    }
    ^ acc
}

// Affine x-coordinate of a Jacobian point: X / Z^2 mod p.
@ __jaffine_x Jac q BigInt p → BigInt {
    : BigInt zsq ( __fsqr . q z p )
    : BigInt zinv ( __finv zsq p )
    : BigInt x ( __fmul . q x zinv p )
    ( bigint_free zsq )
    ( bigint_free zinv )
    ^ x
}

// Affine y-coordinate of a Jacobian point: Y / Z^3 mod p.
@ __jaffine_y Jac q BigInt p → BigInt {
    : BigInt zsq ( __fsqr . q z p )
    : BigInt zcb ( __fmul zsq . q z p )
    : BigInt zinv ( __finv zcb p )
    : BigInt y ( __fmul . q y zinv p )
    ( bigint_free zsq )
    ( bigint_free zcb )
    ( bigint_free zinv )
    ^ y
}

// ── ECDHE over NIST P-256 (secp256r1) ─────────────────────────────
// The TLS 1.3 secp256r1 group (RFC 8446 §4.2.8.2 / RFC 8422): the
// public key is an uncompressed point 0x04 || X(32) || Y(32), and the
// shared secret is the 32-byte big-endian X of scalar·peer. `scalar` is
// the 32-byte ephemeral private key. Reuses the curve arithmetic above.

// Private scalar → 65-byte uncompressed public point.
@ p256_ecdh_keygen ( Vec u ) scalar → ( Vec u ) {
    : BigInt p ( __p256_p )
    : Jac G @ Jac { ( __p256_gx ) ( __p256_gy ) ( bigint_from_i 1 ) F }
    : Jac Q ( __jmul scalar G p )
    : BigInt x ( __jaffine_x Q p )
    : BigInt y ( __jaffine_y Q p )
    : ( Vec u ) xb ( bigint_to_bytes_be x 32 )
    : ( Vec u ) yb ( bigint_to_bytes_be y 32 )
    : ( Vec u ) out ( vec_with_cap [u] 65 )
    ( vec_push [u] out # u 4 )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] out ?? ( vec_get [u] xb k ) { T b → b F _ → # u 0 } ) = k + k 1 }
    = k 0
    ~ < k 32 { ( vec_push [u] out ?? ( vec_get [u] yb k ) { T b → b F _ → # u 0 } ) = k + k 1 }
    ( bigint_free p ) ( __jfree G ) ( __jfree Q )
    ( bigint_free x ) ( bigint_free y ) ( vec_free [u] xb ) ( vec_free [u] yb )
    ^ out
}

// scalar · peer-point → 32-byte shared X. Returns [] on a malformed peer.
@ p256_ecdh_shared ( Vec u ) scalar ( Vec u ) peer → ( Vec u ) {
    ? != ( vec_len [u] peer ) 65 { ^ ( vec_new [u] ) } {}
    ? != ?? ( vec_get [u] peer 0 ) { T x → # i x F _ → 0 } 4 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) qxb ( bytes_slice peer 1 33 )
    : ( Vec u ) qyb ( bytes_slice peer 33 65 )
    : BigInt qx ( bigint_from_bytes_be qxb )
    : BigInt qy ( bigint_from_bytes_be qyb )
    : BigInt p ( __p256_p )
    : Jac Q @ Jac { qx qy ( bigint_from_i 1 ) F }
    : Jac R ( __jmul scalar Q p )
    : BigInt rx ( __jaffine_x R p )
    : ( Vec u ) out ( bigint_to_bytes_be rx 32 )
    ( vec_free [u] qxb ) ( vec_free [u] qyb )
    ( bigint_free p ) ( __jfree Q ) ( __jfree R ) ( bigint_free rx )
    ^ out
}

// ── verify ────────────────────────────────────────────────────────
// Both NIST P-256 and P-384 use a = -3, so the Jacobian point ops above
// are curve-independent; this core takes the curve constants and the
// coordinate byte length. It consumes p / nn / gx / gy.
@ __ecdsa_verify BigInt p BigInt nn BigInt gx BigInt gy i clen ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ? != ( vec_len [u] point ) + 1 * 2 clen {
        ( bigint_free p ) ( bigint_free nn ) ( bigint_free gx ) ( bigint_free gy )
        ^ F
    } {}
    ? != ?? ( vec_get [u] point 0 ) { T x → # i x F _ → 0 } 4 {
        ( bigint_free p ) ( bigint_free nn ) ( bigint_free gx ) ( bigint_free gy )
        ^ F
    } {}

    : ( Vec u ) qxb ( bytes_slice point 1 + 1 clen )
    : ( Vec u ) qyb ( bytes_slice point + 1 clen + 1 * 2 clen )
    : BigInt qx ( bigint_from_bytes_be qxb )
    : BigInt qy ( bigint_from_bytes_be qyb )
    ( vec_free [u] qxb )
    ( vec_free [u] qyb )

    : BigInt br ( bigint_from_bytes_be r )
    : BigInt bs ( bigint_from_bytes_be s )
    : BigInt z ( bigint_from_bytes_be hash )
    : BigInt one ( bigint_from_i 1 )

    : ~ b ok T
    // r,s must be in [1, n-1]
    ? < ( bigint_cmp br one ) 0 { = ok F } {}
    ? < ( bigint_cmp bs one ) 0 { = ok F } {}
    ? >= ( bigint_cmp br nn ) 0 { = ok F } {}
    ? >= ( bigint_cmp bs nn ) 0 { = ok F } {}

    : ~ b result F
    ? ok {
        : BigInt zr ( bigint_rem z nn )
        : BigInt w ( __finv bs nn )  // s^-1 mod n
        : BigInt u1m ( bigint_mul zr w )
        : BigInt u1 ( bigint_rem u1m nn )
        : BigInt u2m ( bigint_mul br w )
        : BigInt u2 ( bigint_rem u2m nn )
        : ( Vec u ) u1b ( bigint_to_bytes_be u1 0 )
        : ( Vec u ) u2b ( bigint_to_bytes_be u2 0 )

        : Jac G @ Jac { gx gy ( bigint_from_i 1 ) F }
        : Jac Q @ Jac { qx qy ( bigint_from_i 1 ) F }
        : Jac p1 ( __jmul u1b G p )
        : Jac p2 ( __jmul u2b Q p )
        : Jac R ( __jadd p1 p2 p )
        ? . R inf { = result F } {
            : BigInt rx ( __jaffine_x R p )
            : BigInt rxn ( bigint_rem rx nn )
            = result == ( bigint_cmp rxn br ) 0
            ( bigint_free rx )
            ( bigint_free rxn )
        }
        ( __jfree G ) ( __jfree Q ) ( __jfree p1 ) ( __jfree p2 ) ( __jfree R )
        ( bigint_free zr ) ( bigint_free w ) ( bigint_free u1m ) ( bigint_free u1 )
        ( bigint_free u2m ) ( bigint_free u2 ) ( vec_free [u] u1b ) ( vec_free [u] u2b )
    } {
        ( bigint_free qx )
        ( bigint_free qy )
        ( bigint_free gx )
        ( bigint_free gy )
    }
    ( bigint_free p ) ( bigint_free nn ) ( bigint_free br ) ( bigint_free bs )
    ( bigint_free z ) ( bigint_free one )
    ^ result
}

@ ecdsa_p256_verify ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ^ ( __ecdsa_verify ( __p256_p ) ( __p256_n ) ( __p256_gx ) ( __p256_gy ) 32 point r s hash )
}

@ ecdsa_p384_verify ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ^ ( __ecdsa_verify ( __p384_p ) ( __p384_n ) ( __p384_gx ) ( __p384_gy ) 48 point r s hash )
}
