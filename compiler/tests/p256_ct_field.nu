// p256_ct_field.nu — the constant-time GF(p256) field + scalar multiply
// (std/p256_field, Montgomery CIOS + RCB complete addition) cross-checked
// against the KAT-verified bigint reference. Deterministic (fixed RNG seeds).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bigint.nu`
$ `stdlib/std/rng.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/p256_field.nu`

@ __bg ( Vec u ) v i k → i { ?? ( vec_get [u] v k ) { T b → ^ # i b F _ → ^ 0 } }

@ hx s h → ( Vec u ) { ?? ( bytes_from_hex h ) { T v → v F _ → ( vec_new [u] ) } }

@ bgh s h → BigInt { : ( Vec u ) v ( hx h ) : BigInt r ( bigint_from_bytes_be v ) ( vec_free [u] v ) ^ r }

@ p256p → BigInt { ^ ( bgh `ffffffff00000001000000000000000000000000ffffffffffffffffffffffff` ) }

@ to_limbs BigInt x → ( Vec i ) {
    : ( Vec u ) be ( bigint_to_bytes_be x 32 )
    : ( Vec i ) out ( vec_with_cap [i] 4 )
    : ~ i k 0
    ~ < k 4 {
        : i base - 24 * 8 k
        : ~ u64 acc 0
        : ~ i j 0
        ~ < j 8 {
            = acc | << acc 8 # u64 ( __bg be + base j )
            = j + j 1
        }
        ( vec_push [i] out # i acc )
        = k + k 1
    }
    ( vec_free [u] be ) ^ out
}

@ from_limbs ( Vec i ) v → BigInt {
    : ( Vec u ) be ( vec_with_cap [u] 32 )
    : ~ i k 3
    ~ >= k 0 {
        : u64 lk # u64 ?? ( vec_get [i] v k ) { T x → x F _ → 0 }
        : ~ i sh 56
        ~ >= sh 0 {
            ( vec_push [u] be # u & # i >> lk sh 255 )
            = sh - sh 8
        }
        = k - k 1
    }
    : BigInt r ( bigint_from_bytes_be be ) ( vec_free [u] be ) ^ r
}

@ eq BigInt a BigInt b → b { ^ == ( bigint_cmp a b ) 0 }

@ rand_fp Rng g BigInt p → BigInt {
    : ( Vec u ) be ( vec_with_cap [u] 32 )
    : ~ i k 0 ~ < k 32 { ( vec_push [u] be # u & ( rng_next g ) 255 ) = k + k 1 }
    : BigInt x ( bigint_from_bytes_be be ) ( vec_free [u] be )
    : BigInt r ( bigint_rem x p ) ( bigint_free x ) ^ r
}

// ── the reference: a test-local BigInt Jacobian ladder ────────────
// This used to live in std/ecdsa_p256 as its verify path; the stdlib now
// verifies on the fixed-limb field, so the slow BigInt ladder survives
// here as the independent oracle it always really was. It shares no code
// with the implementation under test — different coordinates (Jacobian
// vs homogeneous projective), different field (BigInt trial division vs
// Montgomery CIOS), different addition formula (classic split-case vs
// RCB complete) — and needs no constant-time discipline: plain branches.

@ fmul BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_mul a b )
    : BigInt r ( bigint_rem t p )
    ( bigint_free t )
    ^ r
}

@ fadd BigInt a BigInt b BigInt p → BigInt {
    : BigInt t ( bigint_add a b )
    : BigInt r ( bigint_rem t p )
    ( bigint_free t )
    ^ r
}

@ fsub BigInt a BigInt b BigInt p → BigInt {
    : BigInt t1 ( bigint_add a p )
    : BigInt t2 ( bigint_sub t1 b )
    : BigInt r ( bigint_rem t2 p )
    ( bigint_free t1 )
    ( bigint_free t2 )
    ^ r
}

@ fsml i k BigInt a BigInt p → BigInt {
    : BigInt kk ( bigint_from_i k )
    : BigInt r ( fmul kk a p )
    ( bigint_free kk )
    ^ r
}

@ finv BigInt a BigInt p → BigInt {
    : BigInt two ( bigint_from_i 2 )
    : BigInt pm2 ( bigint_sub p two )
    : BigInt r ( bigint_modpow a pm2 p )
    ( bigint_free two )
    ( bigint_free pm2 )
    ^ r
}

: RJac { BigInt x BigInt y BigInt z b inf }

@ rj_inf → RJac {
    ^ @ RJac { ( bigint_from_i 1 ) ( bigint_from_i 1 ) ( bigint_from_i 0 ) T }
}

@ rj_free RJac q → v {
    ( bigint_free . q x )
    ( bigint_free . q y )
    ( bigint_free . q z )
}

@ rj_clone RJac q → RJac {
    ^ @ RJac { ( bigint_clone . q x ) ( bigint_clone . q y ) ( bigint_clone . q z ) . q inf }
}

// Point doubling (a = -3 form).
@ rj_double RJac q BigInt p → RJac {
    ? . q inf { ^ ( rj_clone q ) } {}
    ? ( bigint_is_zero . q y ) { ^ ( rj_inf ) } {}
    : BigInt A ( fmul . q y . q y p )
    : BigInt xa ( fmul . q x A p )
    : BigInt B ( fsml 4 xa p )
    : BigInt a2 ( fmul A A p )
    : BigInt C ( fsml 8 a2 p )
    : BigInt zsq ( fmul . q z . q z p )
    : BigInt xm ( fsub . q x zsq p )
    : BigInt xp ( fadd . q x zsq p )
    : BigInt dm ( fmul xm xp p )
    : BigInt D ( fsml 3 dm p )
    : BigInt dsq ( fmul D D p )
    : BigInt b2 ( fsml 2 B p )
    : BigInt X3 ( fsub dsq b2 p )
    : BigInt bx ( fsub B X3 p )
    : BigInt dbx ( fmul D bx p )
    : BigInt Y3 ( fsub dbx C p )
    : BigInt yz ( fmul . q y . q z p )
    : BigInt Z3 ( fsml 2 yz p )
    ( bigint_free A ) ( bigint_free xa ) ( bigint_free B ) ( bigint_free a2 )
    ( bigint_free C ) ( bigint_free zsq ) ( bigint_free xm ) ( bigint_free xp )
    ( bigint_free dm ) ( bigint_free D ) ( bigint_free dsq ) ( bigint_free b2 )
    ( bigint_free bx ) ( bigint_free dbx ) ( bigint_free yz )
    ^ @ RJac { X3 Y3 Z3 F }
}

// Point addition (general Jacobian + Jacobian).
@ rj_add RJac p1 RJac p2 BigInt p → RJac {
    ? . p1 inf { ^ ( rj_clone p2 ) } {}
    ? . p2 inf { ^ ( rj_clone p1 ) } {}
    : BigInt z1sq ( fmul . p1 z . p1 z p )
    : BigInt z2sq ( fmul . p2 z . p2 z p )
    : BigInt u1 ( fmul . p1 x z2sq p )
    : BigInt u2 ( fmul . p2 x z1sq p )
    : BigInt z2cu ( fmul . p2 z z2sq p )
    : BigInt z1cu ( fmul . p1 z z1sq p )
    : BigInt s1 ( fmul . p1 y z2cu p )
    : BigInt s2 ( fmul . p2 y z1cu p )
    : i ucmp ( bigint_cmp u1 u2 )
    : i scmp ( bigint_cmp s1 s2 )
    ? == ucmp 0 {
        ( bigint_free z1sq ) ( bigint_free z2sq ) ( bigint_free u1 ) ( bigint_free u2 )
        ( bigint_free z2cu ) ( bigint_free z1cu ) ( bigint_free s1 ) ( bigint_free s2 )
        ? == scmp 0 { ^ ( rj_double p1 p ) } { ^ ( rj_inf ) }
    } {}
    : BigInt H ( fsub u2 u1 p )
    : BigInt R ( fsub s2 s1 p )
    : BigInt hsq ( fmul H H p )
    : BigInt hcu ( fmul H hsq p )
    : BigInt u1hsq ( fmul u1 hsq p )
    : BigInt rsq ( fmul R R p )
    : BigInt t1 ( fsub rsq hcu p )
    : BigInt u1hsq2 ( fsml 2 u1hsq p )
    : BigInt X3 ( fsub t1 u1hsq2 p )
    : BigInt t2 ( fsub u1hsq X3 p )
    : BigInt rt2 ( fmul R t2 p )
    : BigInt s1hcu ( fmul s1 hcu p )
    : BigInt Y3 ( fsub rt2 s1hcu p )
    : BigInt z1z2 ( fmul . p1 z . p2 z p )
    : BigInt Z3 ( fmul H z1z2 p )
    ( bigint_free z1sq ) ( bigint_free z2sq ) ( bigint_free u1 ) ( bigint_free u2 )
    ( bigint_free z2cu ) ( bigint_free z1cu ) ( bigint_free s1 ) ( bigint_free s2 )
    ( bigint_free H ) ( bigint_free R ) ( bigint_free hsq ) ( bigint_free hcu )
    ( bigint_free u1hsq ) ( bigint_free rsq ) ( bigint_free t1 ) ( bigint_free u1hsq2 )
    ( bigint_free t2 ) ( bigint_free rt2 ) ( bigint_free s1hcu ) ( bigint_free z1z2 )
    ^ @ RJac { X3 Y3 Z3 F }
}

// k · P over the bits of k (big-endian byte view), MSB to LSB.
@ rj_mul ( Vec u ) k RJac base BigInt p → RJac {
    : ~ RJac acc ( rj_inf )
    : i n ( vec_len [u] k )
    : ~ i bi 0
    ~ < bi n {
        : i byte ( __bg k bi )
        : ~ i bit 7
        ~ >= bit 0 {
            : RJac d ( rj_double acc p )
            ( rj_free acc )
            = acc d
            ? != 0 & 1 >> byte bit {
                : RJac t ( rj_add acc base p )
                ( rj_free acc )
                = acc t
            } {}
            = bit - bit 1
        }
        = bi + bi 1
    }
    ^ acc
}

// Affine x / y of a Jacobian point: X / Z^2, Y / Z^3 mod p.
@ rj_affine_x RJac q BigInt p → BigInt {
    : BigInt zsq ( fmul . q z . q z p )
    : BigInt zinv ( finv zsq p )
    : BigInt x ( fmul . q x zinv p )
    ( bigint_free zsq )
    ( bigint_free zinv )
    ^ x
}

@ rj_affine_y RJac q BigInt p → BigInt {
    : BigInt zsq ( fmul . q z . q z p )
    : BigInt zcb ( fmul zsq . q z p )
    : BigInt zinv ( finv zcb p )
    : BigInt y ( fmul . q y zinv p )
    ( bigint_free zsq )
    ( bigint_free zcb )
    ( bigint_free zinv )
    ^ y
}

@ main → i {
    : BigInt p ( p256p )
    : Rng g ( rng_seed 0x50607080 )
    : ~ i ff 0
    : ~ i t 0
    ~ < t 400 {
        : BigInt a ( rand_fp g p ) : BigInt b ( rand_fp g p )
        : ( Vec i ) al ( to_limbs a ) : ( Vec i ) bl ( to_limbs b )
        : ( Vec i ) am ( p256ct_to_mont al ) : ( Vec i ) bm ( p256ct_to_mont bl )
        : ( Vec i ) pm ( p256ct_mul am bm ) : ( Vec i ) pr ( p256ct_from_mont pm )
        : BigInt gm ( from_limbs pr ) : BigInt ab ( bigint_mul a b ) : BigInt rm ( bigint_rem ab p )
        ? ! ( eq gm rm ) { = ff + ff 1 } {}
        : ( Vec i ) sl ( p256ct_add al bl ) : BigInt ga ( from_limbs sl )
        : BigInt apb ( bigint_add a b ) : BigInt ra ( bigint_rem apb p )
        ? ! ( eq ga ra ) { = ff + ff 1 } {}
        ? ! ( bigint_is_zero a ) {
            : ( Vec i ) iv ( p256ct_inv am ) : ( Vec i ) ivp ( p256ct_from_mont iv )
            : BigInt gi ( from_limbs ivp ) : BigInt ck ( bigint_mul a gi ) : BigInt ckr ( bigint_rem ck p )
            : BigInt one ( bigint_from_i 1 )
            ? ! ( eq ckr one ) { = ff + ff 1 } {}
            ( bigint_free gi ) ( bigint_free ck ) ( bigint_free ckr ) ( bigint_free one )
            ( vec_free [i] iv ) ( vec_free [i] ivp )
        } {}
        ( bigint_free a ) ( bigint_free b ) ( bigint_free gm ) ( bigint_free ab ) ( bigint_free rm )
        ( bigint_free ga ) ( bigint_free apb ) ( bigint_free ra )
        ( vec_free [i] al ) ( vec_free [i] bl ) ( vec_free [i] am ) ( vec_free [i] bm )
        ( vec_free [i] pm ) ( vec_free [i] pr ) ( vec_free [i] sl )
        = t + t 1
    }
    // Scalar multiply against the INDEPENDENT reference ladder above.
    // (It must not be compared against p256_ecdh_keygen: that calls the
    // very ladder under test, so the check would be vacuous.)
    : BigInt gx ( bgh `6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296` )
    : BigInt gy ( bgh `4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5` )
    : ( Vec i ) gxl ( to_limbs gx ) : ( Vec i ) gyl ( to_limbs gy )
    : Rng g2 ( rng_seed 0xabcdef01 )
    : ~ i sf 0
    : ~ i s 0
    ~ < s 60 {
        : ( Vec u ) k ( vec_with_cap [u] 32 )
        : ~ i j 0 ~ < j 32 { ( vec_push [u] k # u & ( rng_next g2 ) 255 ) = j + j 1 }
        : RJac gj @ RJac { ( bigint_clone gx ) ( bigint_clone gy ) ( bigint_from_i 1 ) F }
        : RJac rj ( rj_mul k gj p )
        : BigInt rx ( rj_affine_x rj p )
        : BigInt ry ( rj_affine_y rj p )
        : ( Vec u ) refx ( bigint_to_bytes_be rx 32 )
        : ( Vec u ) refy ( bigint_to_bytes_be ry 32 )
        : ( Vec u ) mine ( p256ct_scalarmult k gxl gyl )
        : ~ b ok == ( vec_len [u] mine ) 64
        : ~ i c 0 ~ & ok < c 32 { ? != ( __bg refx c ) ( __bg mine c ) { = ok F } {} = c + c 1 }
        : ~ i c2 0 ~ & ok < c2 32 { ? != ( __bg refy c2 ) ( __bg mine + 32 c2 ) { = ok F } {} = c2 + c2 1 }
        ? ! ok { = sf + sf 1 } {}
        ( bigint_free rx ) ( bigint_free ry ) ( rj_free rj ) ( rj_free gj )
        ( vec_free [u] refx ) ( vec_free [u] refy )
        ( vec_free [u] k ) ( vec_free [u] mine )
        = s + s 1
    }
    ( nurl_print `field 400 trials, scalarmult 60 trials\n` )
    ( nurl_print ? & == ff 0 == sf 0 `p256 ct: PASS\n` `p256 ct: FAIL\n` )
    ( bigint_free p ) ( rng_free g ) ( bigint_free gx ) ( bigint_free gy )
    ( vec_free [i] gxl ) ( vec_free [i] gyl ) ( rng_free g2 )
    ^ 0
}
