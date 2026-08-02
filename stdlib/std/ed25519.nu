// stdlib/std/ed25519.nu — pure-NURL Ed25519 sign / verify (RFC 8032), no
// OpenSSL. Reuses x25519.nu's GF(2^255−19) field arithmetic (_A/_Z/_M/_S/
// __car25519/_sel25519/_inv25519/_pack25519/_unpack25519) and SHA-512
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

@ __ed_pt → EdPt { ^ @ EdPt { ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) } }

@ __ed_pt_free EdPt p → v {
    ( vec_free [i] . p x ) ( vec_free [i] . p y ) ( vec_free [i] . p z ) ( vec_free [i] . p t )
}

// ── constants ──────────────────────────────────────────────────────
// Built by unpacking the 32-byte little-endian forms of TweetNaCl's gf
// constants (the high-bit mask in _unpack25519 is a no-op here).
@ __ed_const s hex → ( Vec i ) {
    : ( Vec u ) b ?? ( bytes_from_hex hex ) { T v → v F _ → ( vec_new [u] ) }
    : ( Vec i ) g ( _unpack25519 b )
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

// Strict little-endian "less than" on two 32-byte arrays (scan MSB→LSB).
@ __ed_lt32 ( Vec u ) aa ( Vec u ) bb → b {
    : ~ i k 31
    : ~ i res 0
    ~ & == res 0 >= k 0 {
        : i ak ( _x_bget aa k )
        : i bk ( _x_bget bb k )
        ? < ak bk { = res 1 } {}
        ? > ak bk { = res -1 } {}
        = k - k 1
    }
    ^ == res 1
}

// M6: a signature scalar S must satisfy 0 ≤ S < L. Otherwise (R, S+L)
// re-verifies as a second valid signature for the same message (Ed25519
// malleability / SUF-CMA break). `cap_S` is the 32-byte little-endian S.
@ __ed_s_canonical ( Vec u ) cap_S → b {
    : ( Vec u ) Lc ( __ed_L )
    : b ok ( __ed_lt32 cap_S Lc )
    ( vec_free [u] Lc )
    ^ ok
}

// M7: an encoded point's y-coordinate must be canonical — the 255-bit value
// (sign bit cleared) must be < p = 2^255−19. Non-canonical encodings let
// distinct byte strings map to the same point (libsodium / ZIP-215 class).
@ __ed_y_canonical ( Vec u ) enc → b {
    : ( Vec u ) m ( __ed_b32 enc 0 )
    ( _bset m 31 & ( _x_bget m 31 ) 127 )  // clear the sign bit
    : ( Vec u ) pc ?? ( bytes_from_hex `edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f` ) { T v → v F _ → ( vec_new [u] ) }
    : b ok ( __ed_lt32 m pc )
    ( vec_free [u] m ) ( vec_free [u] pc )
    ^ ok
}

// ── byte helpers ───────────────────────────────────────────────────
// Copy 32 bytes of `src` starting at `off`.
@ __ed_b32 ( Vec u ) src i off → ( Vec u ) {
    : ( Vec u ) o ( _zeros_u 32 )
    : ~ i k 0
    ~ < k 32 { ( _bset o k ( _x_bget src + off k ) ) = k + k 1 }
    ^ o
}
// Append all of `b` onto `a` in place.
@ __ed_app ( Vec u ) a ( Vec u ) b → v {
    : i n ( vec_len [u] b )
    : ~ i k 0
    ~ < k n { ( vec_push [u] a # u ( _x_bget b k ) ) = k + k 1 }
}

// ── point operations (TweetNaCl) ───────────────────────────────────

// p ← p + q  (extended coords; d2 = 2·d).
// The nine field temporaries one Edwards addition needs, held for a whole
// scalar multiply instead of being allocated and freed inside each one.
// The ladder performs 512 additions, so allocating nine gf per addition
// cost ~9000 allocations per scalar multiply — a quarter of the run time,
// in the allocator, for a routine that does nine field multiplies.
: EdScratch {
    ( Vec i ) a ( Vec i ) b ( Vec i ) c ( Vec i ) d ( Vec i ) e
    ( Vec i ) f ( Vec i ) g ( Vec i ) h ( Vec i ) tt
}

@ __ed_scr_new → EdScratch {
    ^ @ EdScratch {
        ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero )
        ( _gf_zero ) ( _gf_zero ) ( _gf_zero ) ( _gf_zero )
    }
}

@ __ed_scr_free EdScratch s → v {
    ( vec_free [i] . s a ) ( vec_free [i] . s b ) ( vec_free [i] . s c )
    ( vec_free [i] . s d ) ( vec_free [i] . s e ) ( vec_free [i] . s f )
    ( vec_free [i] . s g ) ( vec_free [i] . s h ) ( vec_free [i] . s tt )
}

// p ← p + q, twisted-Edwards extended coordinates. `p` may be `q` (the
// ladder doubles that way): every operand is read into the scratch before
// any of p's coordinates is written.
@ __ed_add EdScratch sc EdPt p EdPt q ( Vec i ) d2 → v {
    : ( Vec i ) a . sc a : ( Vec i ) b . sc b : ( Vec i ) c . sc c
    : ( Vec i ) d . sc d : ( Vec i ) e . sc e : ( Vec i ) f . sc f
    : ( Vec i ) g . sc g : ( Vec i ) h . sc h : ( Vec i ) tt . sc tt
    ( _Z a . p y . p x )
    ( _Z tt . q y . q x )
    ( _M a a tt )
    ( _A b . p x . p y )
    ( _A tt . q x . q y )
    ( _M b b tt )
    ( _M c . p t . q t )
    ( _M c c d2 )
    ( _M d . p z . q z )
    ( _A d d d )
    ( _Z e b a )
    ( _Z f d c )
    ( _A g d c )
    ( _A h b a )
    ( _M . p x e f )
    ( _M . p y h g )
    ( _M . p z g f )
    ( _M . p t e h )
}

// ── the window table ──────────────────────────────────────────────
// Sixteen multiples of the input point, 0·Q … 15·Q, in one flat limb
// vector: entry d occupies [d·40, d·40+40) as x‖y‖z‖t, ten limbs each.

@ __ed_tbl_put ( Vec i ) tbl i d EdPt q → v {
    : *i tb ( vec_data [i] tbl )
    : *i qx ( vec_data [i] . q x )
    : *i qy ( vec_data [i] . q y )
    : *i qz ( vec_data [i] . q z )
    : *i qt ( vec_data [i] . q t )
    : i base * d 40
    : ~ i k 0
    ~ < k 10 {
        = . tb + base k . qx k
        = . tb + + base 10 k . qy k
        = . tb + + base 20 k . qz k
        = . tb + + base 30 k . qt k
        = k + k 1
    }
}

// Read entry `digit` into `dst`. `digit` is four bits of the SECRET
// scalar, so the table is never indexed by it: all sixteen entries are
// read, every window, and merged under a mask that is all-ones exactly
// when d == digit. The mask is arithmetic rather than a comparison —
// `d ^ digit` is zero only on a match, and subtracting one from zero
// borrows into the top bit, which nothing else can set for a 4-bit
// value. Note the mask is a FULL 64-bit −1: gf limbs are signed, so a
// negative limb has its high bits set and a 32-bit mask would clip it.
@ __ed_tbl_get_d EdPt dst ( Vec i ) tbl i digit → v {
    : *i tb ( vec_data [i] tbl )
    : *i dx ( vec_data [i] . dst x )
    : *i dy ( vec_data [i] . dst y )
    : *i dz ( vec_data [i] . dst z )
    : *i dt ( vec_data [i] . dst t )
    : ~ i k 0
    ~ < k 10 { = . dx k 0 = . dy k 0 = . dz k 0 = . dt k 0 = k + k 1 }
    : ~ i d 0
    ~ < d 16 {
        : u64 z ^^ # u64 d # u64 digit
        : i mask - 0 # i >> - z 1 63
        : i base * d 40
        : ~ i j 0
        ~ < j 10 {
            = . dx j | . dx j & mask . tb + base j
            = . dy j | . dy j & mask . tb + + base 10 j
            = . dz j | . dz j & mask . tb + + base 20 j
            = . dt j | . dt j & mask . tb + + base 30 j
            = j + j 1
        }
        = d + d 1
    }
}

// p ← s · q  (s is a little-endian scalar). p is set to the identity
// first.
//
// FIXED 4-BIT WINDOW over the same complete Edwards addition. The scalar
// is consumed a nibble at a time, most significant first: four doublings
// shift the accumulator up by sixteen, then one addition brings in
// digit·Q read out of the window table. That is 4·64 + 64 + 14 = 334
// point additions for a 32-byte scalar, where the bit-at-a-time ladder
// it replaces needed 512.
//
// Constant time on the same terms as the ladder it replaces: the step
// count is fixed at 2·len(scalar bytes) windows, the digit selects by
// mask and never by address, and digit 0 reads the identity, which the
// complete addition formula absorbs. `w` and the nibble position are
// public loop counters.
@ __ed_scalarmult EdPt p EdPt q ( Vec u ) s ( Vec i ) d2 → v {
    : EdScratch sc ( __ed_scr_new )
    : ( Vec i ) tbl ( _zeros_i 640 )
    : EdPt cur ( __ed_pt )
    : EdPt sel ( __ed_pt )
    // T[0] = identity (0, 1, 1, 0); T[1] = Q; T[d] = T[d-1] + Q.
    ( _vset . cur y 0 1 )
    ( _vset . cur z 0 1 )
    ( __ed_tbl_put tbl 0 cur )
    ( __ed_tbl_put tbl 1 q )
    ( __ed_pt_copy cur q )
    : ~ i d 2
    ~ < d 16 {
        ( __ed_add sc cur q d2 )
        ( __ed_tbl_put tbl d cur )
        = d + d 1
    }
    // p ← identity
    : ~ i z 0
    ~ < z 10 { ( _vset . p x z 0 ) ( _vset . p y z 0 ) ( _vset . p z z 0 ) ( _vset . p t z 0 ) = z + z 1 }
    ( _vset . p y 0 1 )
    ( _vset . p z 0 1 )
    : i nwin * ( vec_len [u] s ) 2
    : ~ i w 0
    ~ < w nwin {
        ( __ed_add sc p p d2 )
        ( __ed_add sc p p d2 )
        ( __ed_add sc p p d2 )
        ( __ed_add sc p p d2 )
        // nibble n counts from the bottom of the little-endian scalar.
        : i n - - nwin 1 w
        : i bv ( _x_bget s >> n 1 )
        : i digit ? == & n 1 1 & 15 >> bv 4 & 15 bv
        ( __ed_tbl_get_d sel tbl digit )
        ( __ed_add sc p sel d2 )
        = w + w 1
    }
    ( __ed_pt_free cur ) ( __ed_pt_free sel )
    ( vec_free [i] tbl )
    ( __ed_scr_free sc )
}

@ __ed_pt_copy EdPt dst EdPt src → v {
    ( _gf_into . dst x . src x )
    ( _gf_into . dst y . src y )
    ( _gf_into . dst z . src z )
    ( _gf_into . dst t . src t )
}

// p ← s · B  (B the Ed25519 base point).
@ __ed_scalarbase EdPt p ( Vec u ) s ( Vec i ) d2 → v {
    : EdPt q ( __ed_pt )
    : ( Vec i ) bx ( __ed_X )
    : ( Vec i ) by ( __ed_Y )
    ( _gf_into . q x bx )
    ( _gf_into . q y by )
    ( _vset . q z 0 1 )
    ( _M . q t bx by )
    ( __ed_scalarmult p q s d2 )
    ( __ed_pt_free q )
    ( vec_free [i] bx ) ( vec_free [i] by )
}

// parity = low bit of the canonical packing.
@ __ed_par25519 ( Vec i ) a → i {
    : ( Vec u ) d ( _pack25519 a )
    : i p & ( _x_bget d 0 ) 1
    ( vec_free [u] d )
    ^ p
}

// 1 when a ≠ b (packed), else 0.
@ __ed_neq25519 ( Vec i ) a ( Vec i ) b → i {
    : ( Vec u ) pa ( _pack25519 a )
    : ( Vec u ) pb ( _pack25519 b )
    : ~ i diff 0
    : ~ i k 0
    ~ < k 32 { = diff | diff ^^ ( _x_bget pa k ) ( _x_bget pb k ) = k + k 1 }
    ( vec_free [u] pa ) ( vec_free [u] pb )
    ^ ? == diff 0 0 1
}

// o ← i^((p-5)/8)  (used for the modular square root in unpacking).
@ __ed_pow2523 ( Vec i ) o ( Vec i ) inp → v {
    : ( Vec i ) c ( _gf_copy inp )
    : ~ i a 250
    ~ >= a 0 {
        ( _S c c )
        ? != a 1 { ( _M c c inp ) } {}
        = a - a 1
    }
    ( _gf_into o c )
    ( vec_free [i] c )
}

// Pack a point to 32 bytes (affine y with the x-parity in the top bit).
@ __ed_pack EdPt p → ( Vec u ) {
    : ( Vec i ) zi ( _gf_copy . p z )
    ( _inv25519 zi )
    : ( Vec i ) tx ( _gf_zero ) ( _M tx . p x zi )
    : ( Vec i ) ty ( _gf_zero ) ( _M ty . p y zi )
    : ( Vec u ) r ( _pack25519 ty )
    : i px ( __ed_par25519 tx )
    ( _bset r 31 ^^ ( _x_bget r 31 ) << px 7 )
    ( vec_free [i] zi ) ( vec_free [i] tx ) ( vec_free [i] ty )
    ^ r
}

// Unpack a packed public key into the NEGATED point r. Returns 0 on success,
// -1 if the encoding is not a valid curve point.
@ __ed_unpackneg EdPt r ( Vec u ) p → i {
    : ( Vec i ) cD ( __ed_D )
    : ( Vec i ) cI ( __ed_I )
    : ( Vec i ) num ( _gf_zero ) : ( Vec i ) den ( _gf_zero )
    : ( Vec i ) den2 ( _gf_zero ) : ( Vec i ) den4 ( _gf_zero ) : ( Vec i ) den6 ( _gf_zero )
    : ( Vec i ) t ( _gf_zero ) : ( Vec i ) chk ( _gf_zero )
    ( _vset . r z 0 1 )
    : ( Vec i ) ry ( _unpack25519 p )
    ( _gf_into . r y ry )
    ( vec_free [i] ry )
    ( _S num . r y )
    ( _M den num cD )
    ( _Z num num . r z )
    ( _A den . r z den )
    ( _S den2 den )
    ( _S den4 den2 )
    ( _M den6 den4 den2 )
    ( _M t den6 num )
    ( _M t t den )
    ( __ed_pow2523 t t )
    ( _M t t num )
    ( _M t t den )
    ( _M t t den )
    ( _M . r x t den )
    ( _S chk . r x )
    ( _M chk chk den )
    ? != ( __ed_neq25519 chk num ) 0 { ( _M . r x . r x cI ) } {}
    ( _S chk . r x )
    ( _M chk chk den )
    : ~ i ret 0
    ? != ( __ed_neq25519 chk num ) 0 { = ret -1 } {}
    ? == ret 0 {
        ? == ( __ed_par25519 . r x ) >> ( _x_bget p 31 ) 7 {
            : ( Vec i ) z0 ( _gf_zero )
            ( _Z . r x z0 . r x )
            ( vec_free [i] z0 )
        } {}
        ( _M . r t . r x . r y )
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
            ( _vset x j + ( _vget x j ) - carry * * 16 ( _vget x i ) ( _x_bget cL - j - i 32 ) )
            = carry >> + ( _vget x j ) 128 8
            ( _vset x j - ( _vget x j ) << carry 8 )
            = j + j 1
        }
        ( _vset x j + ( _vget x j ) carry )
        ( _vset x i 0 )
        = i - i 1
    }
    : ~ i carry 0
    : ~ i j 0
    ~ < j 32 {
        ( _vset x j + ( _vget x j ) - carry * >> ( _vget x 31 ) 4 ( _x_bget cL j ) )
        = carry >> ( _vget x j ) 8
        ( _vset x j & ( _vget x j ) 255 )
        = j + j 1
    }
    : ~ i j2 0
    ~ < j2 32 { ( _vset x j2 - ( _vget x j2 ) * carry ( _x_bget cL j2 ) ) = j2 + j2 1 }
    : ~ i i2 0
    ~ < i2 32 {
        ( _vset x + i2 1 + ( _vget x + i2 1 ) >> ( _vget x i2 ) 8 )
        ( _bset r i2 & ( _vget x i2 ) 255 )
        = i2 + i2 1
    }
    ( vec_free [u] cL )
}

// Reduce a 64-byte value mod L, leaving the 32-byte result in r[0:32].
@ __ed_reduce ( Vec u ) r → v {
    : ( Vec i ) x ( _zeros_i 64 )
    : ~ i i 0
    ~ < i 64 { ( _vset x i ( _x_bget r i ) ) = i + i 1 }
    ( __ed_modL r x )
    ( vec_free [i] x )
}

// ── public API ─────────────────────────────────────────────────────

// Derive the 32-byte public key A from a 32-byte seed.
@ ed25519_pubkey_pure ( Vec u ) seed → ( Vec u ) {
    : ( Vec u ) h ( sha512_pure seed )
    : ( Vec u ) a ( __ed_b32 h 0 )
    ( _bset a 0 & ( _x_bget a 0 ) 248 )
    ( _bset a 31 | & ( _x_bget a 31 ) 127 64 )
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
    ( _bset a 0 & ( _x_bget a 0 ) 248 )
    ( _bset a 31 | & ( _x_bget a 31 ) 127 64 )
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
    : ( Vec i ) x ( _zeros_i 64 )
    : ~ i ii 0
    ~ < ii 32 { ( _vset x ii ( _x_bget rscalar ii ) ) = ii + ii 1 }
    : ~ i i 0
    ~ < i 32 {
        : ~ i j 0
        ~ < j 32 {
            ( _vset x + i j + ( _vget x + i j ) * ( _x_bget khash i ) ( _x_bget a j ) )
            = j + j 1
        }
        = i + i 1
    }
    : ( Vec u ) cap_S ( _zeros_u 32 )
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
    // M6 (S < L) + M7 (canonical y encodings of A and R). Reject otherwise:
    // a non-canonical S enables (R, S+L) malleability; non-canonical A/R
    // break point-uniqueness. Conformant signers always satisfy both.
    ? | | ! ( __ed_s_canonical cap_S ) ! ( __ed_y_canonical cap_A ) ! ( __ed_y_canonical cap_R ) {
        ( __ed_pt_free negA ) ( vec_free [i] d2 )
        ( vec_free [u] cap_A ) ( vec_free [u] cap_R ) ( vec_free [u] cap_S )
        ^ F
    } {}

    // k = SHA512(R || A || msg) mod L
    : ( Vec u ) kin ( vec_new [u] )
    ( __ed_app kin cap_R ) ( __ed_app kin pk ) ( __ed_app kin msg )
    : ( Vec u ) khash ( sha512_pure kin )
    ( __ed_reduce khash )
    : ( Vec u ) kscalar ( __ed_b32 khash 0 )

    // p = k·(−A) + S·B ; valid iff pack(p) == R
    : EdPt p ( __ed_pt ) ( __ed_scalarmult p negA kscalar d2 )
    : EdPt q ( __ed_pt ) ( __ed_scalarbase q cap_S d2 )
    : EdScratch vsc ( __ed_scr_new )
    ( __ed_add vsc p q d2 )
    ( __ed_scr_free vsc )
    : ( Vec u ) tcheck ( __ed_pack p )
    : ~ i diff 0
    : ~ i kk 0
    ~ < kk 32 { = diff | diff ^^ ( _x_bget cap_R kk ) ( _x_bget tcheck kk ) = kk + kk 1 }

    ( __ed_pt_free negA ) ( __ed_pt_free p ) ( __ed_pt_free q ) ( vec_free [i] d2 )
    ( vec_free [u] cap_A ) ( vec_free [u] cap_R ) ( vec_free [u] cap_S )
    ( vec_free [u] kin ) ( vec_free [u] khash ) ( vec_free [u] kscalar ) ( vec_free [u] tcheck )
    ^ == diff 0
}
