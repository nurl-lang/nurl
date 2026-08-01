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
    : ( Vec i ) out ( vec_with_cap [i] 8 )
    : ~ i k 0
    ~ < k 8 {
        ( vec_push [i] out | | | ( __bg be - 31 * 4 k ) << ( __bg be - 30 * 4 k ) 8
        << ( __bg be - 29 * 4 k ) 16 << ( __bg be - 28 * 4 k ) 24 )
        = k + k 1
    }
    ( vec_free [u] be ) ^ out
}

@ from_limbs ( Vec i ) v → BigInt {
    : ( Vec u ) be ( vec_with_cap [u] 32 )
    : ~ i k 7
    ~ >= k 0 {
        : i lk ?? ( vec_get [i] v k ) { T x → x F _ → 0 }
        ( vec_push [u] be # u & >> lk 24 255 ) ( vec_push [u] be # u & >> lk 16 255 )
        ( vec_push [u] be # u & >> lk 8 255 ) ( vec_push [u] be # u & lk 255 )
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
    // scalar mult vs bigint keygen
    : BigInt gx ( bgh `6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296` )
    : BigInt gy ( bgh `4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5` )
    : ( Vec i ) gxl ( to_limbs gx ) : ( Vec i ) gyl ( to_limbs gy )
    : Rng g2 ( rng_seed 0xabcdef01 )
    : ~ i sf 0
    : ~ i s 0
    ~ < s 60 {
        : ( Vec u ) k ( vec_with_cap [u] 32 )
        : ~ i j 0 ~ < j 32 { ( vec_push [u] k # u & ( rng_next g2 ) 255 ) = j + j 1 }
        : ( Vec u ) ref ( p256_ecdh_keygen k )
        : ( Vec u ) mine ( p256ct_scalarmult k gxl gyl )
        : ~ b ok ? & == ( vec_len [u] ref ) 65 == ( vec_len [u] mine ) 64 T F
        : ~ i c 0 ~ & ok < c 64 { ? != ( __bg ref + 1 c ) ( __bg mine c ) { = ok F } {} = c + c 1 }
        ? ! ok { = sf + sf 1 } {}
        ( vec_free [u] k ) ( vec_free [u] ref ) ( vec_free [u] mine )
        = s + s 1
    }
    ( nurl_print `field 400 trials, scalarmult 60 trials\n` )
    ( nurl_print ? & == ff 0 == sf 0 `p256 ct: PASS\n` `p256 ct: FAIL\n` )
    ( bigint_free p ) ( rng_free g ) ( bigint_free gx ) ( bigint_free gy )
    ( vec_free [i] gxl ) ( vec_free [i] gyl ) ( rng_free g2 )
    ^ 0
}
