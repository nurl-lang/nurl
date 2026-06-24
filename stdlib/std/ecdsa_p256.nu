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

// ── verify ────────────────────────────────────────────────────────
@ ecdsa_p256_verify ( Vec u ) point ( Vec u ) r ( Vec u ) s ( Vec u ) hash → b {
    ? != ( vec_len [u] point ) 65 { ^ F } {}
    ? != ?? ( vec_get [u] point 0 ) { T x → # i x F _ → 0 } 4 { ^ F } {}
    : BigInt p ( __p256_p )
    : BigInt nn ( __p256_n )

    : ( Vec u ) qxb ( bytes_slice point 1 33 )
    : ( Vec u ) qyb ( bytes_slice point 33 65 )
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
        : BigInt w ( __finv bs nn )            // s^-1 mod n
        : BigInt u1m ( bigint_mul zr w )
        : BigInt u1 ( bigint_rem u1m nn )
        : BigInt u2m ( bigint_mul br w )
        : BigInt u2 ( bigint_rem u2m nn )
        : ( Vec u ) u1b ( bigint_to_bytes_be u1 0 )
        : ( Vec u ) u2b ( bigint_to_bytes_be u2 0 )

        : Jac G @ Jac { ( __p256_gx ) ( __p256_gy ) ( bigint_from_i 1 ) F }
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
    }
    ( bigint_free p ) ( bigint_free nn ) ( bigint_free br ) ( bigint_free bs )
    ( bigint_free z ) ( bigint_free one )
    ^ result
}
