// stdlib/std/ed25519.nu — pure-NURL Ed25519 sign / verify (RFC 8032), no
// OpenSSL. Reuses x25519.nu's GF(2^255−19) field arithmetic (__A/__Z/__M/__S/
// __car25519/__sel25519/__inv25519/__pack25519/__unpack25519) and SHA-512
// from hash_sha512.nu. The twisted-Edwards point ops, scalar reduction mod
// the group order L, and the sign/verify flow are a TweetNaCl-derived port,
// validated against RFC 8032 test vectors.
//
//   ( ed25519_pubkey_pure seed32 )          → ( Vec u )   32-byte public key A
//   ( ed25519_sign_pure   seed32 msg )      → ( Vec u )   64-byte signature
//   ( ed25519_verify_pure pk32 msg sig64 )  → b

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/x25519.nu`
$ `stdlib/std/hash_sha512.nu`

// A point in extended twisted-Edwards coordinates (X, Y, Z, T). The four gf
// handles share their backing across by-value EdPt copies, so the in-place
// field ops persist through calls.
: EdPt { ( Vec i ) x ( Vec i ) y ( Vec i ) z ( Vec i ) t }

@ __ed_pt → EdPt { ^ @ EdPt { ( __gf_zero ) ( __gf_zero ) ( __gf_zero ) ( __gf_zero ) } }

@ __ed_pt_free EdPt p → v {
    ( vec_free [i] . p x ) ( vec_free [i] . p y ) ( vec_free [i] . p z ) ( vec_free [i] . p t )
}

// ── constants ──────────────────────────────────────────────────────
// Built by unpacking the 32-byte little-endian forms of TweetNaCl's gf
// constants (the high-bit mask in __unpack25519 is a no-op here).
@ __ed_const s hex → ( Vec i ) {
    : ( Vec u ) b ?? ( bytes_from_hex hex ) { T v → v F _ → ( vec_new [u] ) }
    : ( Vec i ) g ( __unpack25519 b )
    ( vec_free [u] b )
    ^ g
}

@ __ed_D → ( Vec i ) { ^ ( __ed_const `a3785913ca4deb75abd841414d0a700098e879777940c78c73fe6f2bee6c0352` ) }

@ __ed_D2 → ( Vec i ) { ^ ( __ed_const `59f1b226949bd6eb56b183829a14e00030d1f3eef2808e19e7fcdf56dcd90624` ) }

@ __ed_X → ( Vec i ) { ^ ( __ed_const `1ad5258f602d56c9b2a7259560c72c695cdcd6fd31e2a4c0fe536ecdd3366921` ) }

@ __ed_Y → ( Vec i ) { ^ ( __ed_const `5866666666666666666666666666666666666666666666666666666666666666` ) }

@ __ed_I → ( Vec i ) { ^ ( __ed_const `b0a00e4a271beec478e42fad0618432fa7d7fb3d99004d2b0bdfc14f8024832b` ) }

// Group order L (little-endian, 32 bytes).
@ __ed_L → ( Vec u ) {
    ^ ?? ( bytes_from_hex `edd3f55c1a631258d69cf7a2def9de1400000000000000000000000000000010` ) { T v → v F _ → ( vec_new [u] ) }
}

// ── byte helpers ───────────────────────────────────────────────────
// Copy 32 bytes of `src` starting at `off`.
@ __ed_b32 ( Vec u ) src i off → ( Vec u ) {
    : ( Vec u ) o ( __zeros_u 32 )
    : ~ i k 0
    ~ < k 32 { ( __bset o k ( __x_bget src + off k ) ) = k + k 1 }
    ^ o
}
// Append all of `b` onto `a` in place.
@ __ed_app ( Vec u ) a ( Vec u ) b → v {
    : i n ( vec_len [u] b )
    : ~ i k 0
    ~ < k n { ( vec_push [u] a # u ( __x_bget b k ) ) = k + k 1 }
}

// ── point operations (TweetNaCl) ───────────────────────────────────

// p ← p + q  (extended coords; d2 = 2·d).
@ __ed_add EdPt p EdPt q ( Vec i ) d2 → v {
    : ( Vec i ) a ( __gf_zero ) : ( Vec i ) b ( __gf_zero ) : ( Vec i ) c ( __gf_zero )
    : ( Vec i ) d ( __gf_zero ) : ( Vec i ) e ( __gf_zero ) : ( Vec i ) f ( __gf_zero )
    : ( Vec i ) g ( __gf_zero ) : ( Vec i ) h ( __gf_zero ) : ( Vec i ) tt ( __gf_zero )
    ( __Z a . p y . p x )
    ( __Z tt . q y . q x )
    ( __M a a tt )
    ( __A b . p x . p y )
    ( __A tt . q x . q y )
    ( __M b b tt )
    ( __M c . p t . q t )
    ( __M c c d2 )
    ( __M d . p z . q z )
    ( __A d d d )
    ( __Z e b a )
    ( __Z f d c )
    ( __A g d c )
    ( __A h b a )
    ( __M . p x e f )
    ( __M . p y h g )
    ( __M . p z g f )
    ( __M . p t e h )
    ( vec_free [i] a ) ( vec_free [i] b ) ( vec_free [i] c ) ( vec_free [i] d )
    ( vec_free [i] e ) ( vec_free [i] f ) ( vec_free [i] g ) ( vec_free [i] h ) ( vec_free [i] tt )
}

@ __ed_cswap EdPt p EdPt q i b → v {
    ( __sel25519 . p x . q x b )
    ( __sel25519 . p y . q y b )
    ( __sel25519 . p z . q z b )
    ( __sel25519 . p t . q t b )
}

// p ← s · q  (s is a 32-byte little-endian scalar). p is set to identity first.
@ __ed_scalarmult EdPt p EdPt q ( Vec u ) s ( Vec i ) d2 → v {
    // identity: (0, 1, 1, 0)
    : ~ i z 0
    ~ < z 16 { ( __vset . p x z 0 ) ( __vset . p y z 0 ) ( __vset . p z z 0 ) ( __vset . p t z 0 ) = z + z 1 }
    ( __vset . p y 0 1 )
    ( __vset . p z 0 1 )
    : ~ i i 255
    ~ >= i 0 {
        : i bit & >> ( __x_bget s / i 8 ) & i 7 1
        ( __ed_cswap p q bit )
        ( __ed_add q p d2 )
        ( __ed_add p p d2 )
        ( __ed_cswap p q bit )
        = i - i 1
    }
}

// p ← s · B  (B the Ed25519 base point).
@ __ed_scalarbase EdPt p ( Vec u ) s ( Vec i ) d2 → v {
    : EdPt q ( __ed_pt )
    : ( Vec i ) bx ( __ed_X )
    : ( Vec i ) by ( __ed_Y )
    ( __gf_into . q x bx )
    ( __gf_into . q y by )
    ( __vset . q z 0 1 )
    ( __M . q t bx by )
    ( __ed_scalarmult p q s d2 )
    ( __ed_pt_free q )
    ( vec_free [i] bx ) ( vec_free [i] by )
}

// parity = low bit of the canonical packing.
@ __ed_par25519 ( Vec i ) a → i {
    : ( Vec u ) d ( __pack25519 a )
    : i p & ( __x_bget d 0 ) 1
    ( vec_free [u] d )
    ^ p
}

// 1 when a ≠ b (packed), else 0.
@ __ed_neq25519 ( Vec i ) a ( Vec i ) b → i {
    : ( Vec u ) pa ( __pack25519 a )
    : ( Vec u ) pb ( __pack25519 b )
    : ~ i diff 0
    : ~ i k 0
    ~ < k 32 { = diff | diff ^^ ( __x_bget pa k ) ( __x_bget pb k ) = k + k 1 }
    ( vec_free [u] pa ) ( vec_free [u] pb )
    ^ ? == diff 0 0 1
}

// o ← i^((p-5)/8)  (used for the modular square root in unpacking).
@ __ed_pow2523 ( Vec i ) o ( Vec i ) inp → v {
    : ( Vec i ) c ( __gf_copy inp )
    : ~ i a 250
    ~ >= a 0 {
        ( __S c c )
        ? != a 1 { ( __M c c inp ) } {}
        = a - a 1
    }
    ( __gf_into o c )
    ( vec_free [i] c )
}

// Pack a point to 32 bytes (affine y with the x-parity in the top bit).
@ __ed_pack EdPt p → ( Vec u ) {
    : ( Vec i ) zi ( __gf_copy . p z )
    ( __inv25519 zi )
    : ( Vec i ) tx ( __gf_zero ) ( __M tx . p x zi )
    : ( Vec i ) ty ( __gf_zero ) ( __M ty . p y zi )
    : ( Vec u ) r ( __pack25519 ty )
    : i px ( __ed_par25519 tx )
    ( __bset r 31 ^^ ( __x_bget r 31 ) << px 7 )
    ( vec_free [i] zi ) ( vec_free [i] tx ) ( vec_free [i] ty )
    ^ r
}

// Unpack a packed public key into the NEGATED point r. Returns 0 on success,
// -1 if the encoding is not a valid curve point.
@ __ed_unpackneg EdPt r ( Vec u ) p → i {
    : ( Vec i ) cD ( __ed_D )
    : ( Vec i ) cI ( __ed_I )
    : ( Vec i ) num ( __gf_zero ) : ( Vec i ) den ( __gf_zero )
    : ( Vec i ) den2 ( __gf_zero ) : ( Vec i ) den4 ( __gf_zero ) : ( Vec i ) den6 ( __gf_zero )
    : ( Vec i ) t ( __gf_zero ) : ( Vec i ) chk ( __gf_zero )
    ( __vset . r z 0 1 )
    : ( Vec i ) ry ( __unpack25519 p )
    ( __gf_into . r y ry )
    ( vec_free [i] ry )
    ( __S num . r y )
    ( __M den num cD )
    ( __Z num num . r z )
    ( __A den . r z den )
    ( __S den2 den )
    ( __S den4 den2 )
    ( __M den6 den4 den2 )
    ( __M t den6 num )
    ( __M t t den )
    ( __ed_pow2523 t t )
    ( __M t t num )
    ( __M t t den )
    ( __M t t den )
    ( __M . r x t den )
    ( __S chk . r x )
    ( __M chk chk den )
    ? != ( __ed_neq25519 chk num ) 0 { ( __M . r x . r x cI ) } {}
    ( __S chk . r x )
    ( __M chk chk den )
    : ~ i ret 0
    ? != ( __ed_neq25519 chk num ) 0 { = ret -1 } {}
    ? == ret 0 {
        ? == ( __ed_par25519 . r x ) >> ( __x_bget p 31 ) 7 {
            : ( Vec i ) z0 ( __gf_zero )
            ( __Z . r x z0 . r x )
            ( vec_free [i] z0 )
        } {}
        ( __M . r t . r x . r y )
    } {}
    ( vec_free [i] cD ) ( vec_free [i] cI ) ( vec_free [i] num ) ( vec_free [i] den )
    ( vec_free [i] den2 ) ( vec_free [i] den4 ) ( vec_free [i] den6 ) ( vec_free [i] t ) ( vec_free [i] chk )
    ^ ret
}

// ── scalar reduction mod L ─────────────────────────────────────────
// r[0:32] ← x mod L, where x is a 64-limb signed accumulator (mutated).
@ __ed_modL ( Vec u ) r ( Vec i ) x → v {
    : ( Vec u ) cL ( __ed_L )
    : ~ i i 63
    ~ >= i 32 {
        : ~ i carry 0
        : ~ i j - i 32
        ~ < j - i 12 {
            ( __vset x j + ( __vget x j ) - carry * * 16 ( __vget x i ) ( __x_bget cL - j - i 32 ) )
            = carry >> + ( __vget x j ) 128 8
            ( __vset x j - ( __vget x j ) << carry 8 )
            = j + j 1
        }
        ( __vset x j + ( __vget x j ) carry )
        ( __vset x i 0 )
        = i - i 1
    }
    : ~ i carry 0
    : ~ i j 0
    ~ < j 32 {
        ( __vset x j + ( __vget x j ) - carry * >> ( __vget x 31 ) 4 ( __x_bget cL j ) )
        = carry >> ( __vget x j ) 8
        ( __vset x j & ( __vget x j ) 255 )
        = j + j 1
    }
    : ~ i j2 0
    ~ < j2 32 { ( __vset x j2 - ( __vget x j2 ) * carry ( __x_bget cL j2 ) ) = j2 + j2 1 }
    : ~ i i2 0
    ~ < i2 32 {
        ( __vset x + i2 1 + ( __vget x + i2 1 ) >> ( __vget x i2 ) 8 )
        ( __bset r i2 & ( __vget x i2 ) 255 )
        = i2 + i2 1
    }
    ( vec_free [u] cL )
}

// Reduce a 64-byte value mod L, leaving the 32-byte result in r[0:32].
@ __ed_reduce ( Vec u ) r → v {
    : ( Vec i ) x ( __zeros_i 64 )
    : ~ i i 0
    ~ < i 64 { ( __vset x i ( __x_bget r i ) ) = i + i 1 }
    ( __ed_modL r x )
    ( vec_free [i] x )
}

// ── public API ─────────────────────────────────────────────────────

// Derive the 32-byte public key A from a 32-byte seed.
@ ed25519_pubkey_pure ( Vec u ) seed → ( Vec u ) {
    : ( Vec u ) h ( sha512_pure seed )
    : ( Vec u ) a ( __ed_b32 h 0 )
    ( __bset a 0 & ( __x_bget a 0 ) 248 )
    ( __bset a 31 | & ( __x_bget a 31 ) 127 64 )
    : ( Vec i ) d2 ( __ed_D2 )
    : EdPt p ( __ed_pt )
    ( __ed_scalarbase p a d2 )
    : ( Vec u ) pk ( __ed_pack p )
    ( __ed_pt_free p ) ( vec_free [i] d2 ) ( vec_free [u] h ) ( vec_free [u] a )
    ^ pk
}

// Sign `msg` with a 32-byte seed → 64-byte signature R||S.
@ ed25519_sign_pure ( Vec u ) seed ( Vec u ) msg → ( Vec u ) {
    : ( Vec u ) h ( sha512_pure seed )
    : ( Vec u ) a ( __ed_b32 h 0 )
    ( __bset a 0 & ( __x_bget a 0 ) 248 )
    ( __bset a 31 | & ( __x_bget a 31 ) 127 64 )
    : ( Vec u ) prefix ( __ed_b32 h 32 )
    : ( Vec i ) d2 ( __ed_D2 )

    // A = public key
    : EdPt pA ( __ed_pt ) ( __ed_scalarbase pA a d2 )
    : ( Vec u ) cap_A ( __ed_pack pA )

    // r = SHA512(prefix || msg) mod L
    : ( Vec u ) rin ( vec_new [u] )
    ( __ed_app rin prefix ) ( __ed_app rin msg )
    : ( Vec u ) rhash ( sha512_pure rin )
    ( __ed_reduce rhash )
    : ( Vec u ) rscalar ( __ed_b32 rhash 0 )

    // R = pack(r·B)
    : EdPt pR ( __ed_pt ) ( __ed_scalarbase pR rscalar d2 )
    : ( Vec u ) cap_R ( __ed_pack pR )

    // k = SHA512(R || A || msg) mod L
    : ( Vec u ) kin ( vec_new [u] )
    ( __ed_app kin cap_R ) ( __ed_app kin cap_A ) ( __ed_app kin msg )
    : ( Vec u ) khash ( sha512_pure kin )
    ( __ed_reduce khash )

    // S = (r + k·a) mod L
    : ( Vec i ) x ( __zeros_i 64 )
    : ~ i ii 0
    ~ < ii 32 { ( __vset x ii ( __x_bget rscalar ii ) ) = ii + ii 1 }
    : ~ i i 0
    ~ < i 32 {
        : ~ i j 0
        ~ < j 32 {
            ( __vset x + i j + ( __vget x + i j ) * ( __x_bget khash i ) ( __x_bget a j ) )
            = j + j 1
        }
        = i + i 1
    }
    : ( Vec u ) cap_S ( __zeros_u 32 )
    ( __ed_modL cap_S x )

    : ( Vec u ) sig ( vec_new [u] )
    ( __ed_app sig cap_R ) ( __ed_app sig cap_S )

    ( __ed_pt_free pA ) ( __ed_pt_free pR ) ( vec_free [i] d2 ) ( vec_free [i] x )
    ( vec_free [u] h ) ( vec_free [u] a ) ( vec_free [u] prefix ) ( vec_free [u] cap_A )
    ( vec_free [u] rin ) ( vec_free [u] rhash ) ( vec_free [u] rscalar ) ( vec_free [u] cap_R )
    ( vec_free [u] kin ) ( vec_free [u] khash ) ( vec_free [u] cap_S )
    ^ sig
}

// Verify a 64-byte signature over `msg` against the 32-byte public key.
@ ed25519_verify_pure ( Vec u ) pk ( Vec u ) msg ( Vec u ) sig → b {
    ? != ( vec_len [u] sig ) 64 { ^ F } {}
    : ( Vec i ) d2 ( __ed_D2 )
    : EdPt negA ( __ed_pt )
    : ( Vec u ) cap_A ( __ed_b32 pk 0 )
    : i okpt ( __ed_unpackneg negA cap_A )
    ? != okpt 0 {
        ( __ed_pt_free negA ) ( vec_free [i] d2 ) ( vec_free [u] cap_A )
        ^ F
    } {}
    : ( Vec u ) cap_R ( __ed_b32 sig 0 )
    : ( Vec u ) cap_S ( __ed_b32 sig 32 )

    // k = SHA512(R || A || msg) mod L
    : ( Vec u ) kin ( vec_new [u] )
    ( __ed_app kin cap_R ) ( __ed_app kin pk ) ( __ed_app kin msg )
    : ( Vec u ) khash ( sha512_pure kin )
    ( __ed_reduce khash )
    : ( Vec u ) kscalar ( __ed_b32 khash 0 )

    // p = k·(−A) + S·B ; valid iff pack(p) == R
    : EdPt p ( __ed_pt ) ( __ed_scalarmult p negA kscalar d2 )
    : EdPt q ( __ed_pt ) ( __ed_scalarbase q cap_S d2 )
    ( __ed_add p q d2 )
    : ( Vec u ) tcheck ( __ed_pack p )
    : ~ i diff 0
    : ~ i kk 0
    ~ < kk 32 { = diff | diff ^^ ( __x_bget cap_R kk ) ( __x_bget tcheck kk ) = kk + kk 1 }

    ( __ed_pt_free negA ) ( __ed_pt_free p ) ( __ed_pt_free q ) ( vec_free [i] d2 )
    ( vec_free [u] cap_A ) ( vec_free [u] cap_R ) ( vec_free [u] cap_S )
    ( vec_free [u] kin ) ( vec_free [u] khash ) ( vec_free [u] kscalar ) ( vec_free [u] tcheck )
    ^ == diff 0
}
