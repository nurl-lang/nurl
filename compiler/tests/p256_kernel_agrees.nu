// p256_kernel_agrees.nu — the P-256 field kernels (the compiler's
// nurl_p256_mulm / nurl_p256_sqrm: on x86-64 the ADX tier or mulq) agree
// with the field's portable NURL form (_p256_mul_port / _p256_sqr_port)
// on every input tried: random elements, elements next to p, small ones,
// and every pair of the edge set, for the multiply and the square. (A
// destination aliasing an operand is the field's own use — the ladder's
// `_p256_sqr_d scr t t` — which the scalar-multiply KATs exercise.) On a
// target without a kernel both sides are the portable form, and the test
// still holds.

$ `stdlib/core/vec.nu`
$ `stdlib/std/p256_field.nu`

: ~ u64 g_x 88172645463325252

@ rnd → u64 {
    = g_x ^^ g_x << g_x 13
    = g_x ^^ g_x >> g_x 7
    = g_x ^^ g_x << g_x 17
    ^ g_x
}

// p = [2^64−1, 2^32−1, 0, 2^64−2^32+1]; an element is < p.
@ below_p ( Vec i ) v → b {
    : u64 p3 18446744069414584321
    : u64 v3 # u64 ( vec_at [i] v 3 )
    ? != v3 p3 { ^ < v3 p3 } {}
    ? != # u64 ( vec_at [i] v 2 ) 0 { ^ F } {}
    : u64 v1 # u64 ( vec_at [i] v 1 )
    ? != v1 4294967295 { ^ < v1 4294967295 } {}
    ^ < # u64 ( vec_at [i] v 0 ) 18446744073709551615
}

@ fe u64 a u64 b u64 c u64 d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v # i a ) ( vec_push [i] v # i b ) ( vec_push [i] v # i c ) ( vec_push [i] v # i d )
    ^ v
}

@ random_fe i kind → ( Vec i ) {
    ~ T {
        : ( Vec i ) v ? == kind 1 ( fe - 18446744073709551615 % ( rnd ) 4096 4294967295 0 18446744069414584321 )
        ? == kind 2 ( fe % ( rnd ) 65536 0 0 0 ) ( fe ( rnd ) ( rnd ) ( rnd ) ( rnd ) )
        ? ( below_p v ) { ^ v } {}
    }
    ^ ( fe 0 0 0 0 )
}

@ same ( Vec i ) x ( Vec i ) y → b {
    ^ & & & == ( vec_at [i] x 0 ) ( vec_at [i] y 0 ) == ( vec_at [i] x 1 ) ( vec_at [i] y 1 ) == ( vec_at [i] x 2 ) ( vec_at [i] y 2 ) == ( vec_at [i] x 3 ) ( vec_at [i] y 3 )
}

// The kernels' entry points are `raw` (four-limb operands, which `fe`
// always builds), so the function calling them vouches for that.
unsafe @ check P256Scratch scr ( Vec i ) a ( Vec i ) b → i {
    : ( Vec i ) k1 ( fe 0 0 0 0 )
    : ( Vec i ) p1 ( fe 0 0 0 0 )
    ( _p256_mul_d scr k1 a b )
    ( _p256_mul_port scr p1 a b )
    : ( Vec i ) k2 ( fe 0 0 0 0 )
    : ( Vec i ) p2 ( fe 0 0 0 0 )
    ( _p256_sqr_d scr k2 a )
    ( _p256_sqr_port scr p2 a )
    ^ + ? ( same k1 p1 ) 0 1 ? ( same k2 p2 ) 0 1
}

@ main → i {
    : P256Scratch scr ( _p256_scr_new )
    : ~ i bad 0
    : ~ i n 0
    : ~ i k 0
    ~ < k 60000 {
        : ( Vec i ) a ( random_fe % k 3 )
        : ( Vec i ) b ( random_fe % / k 3 3 )
        = bad + bad ( check scr a b )
        = n + n 2
        = k + k 1
    }
    // the edge set, every pair
    : ( Vec ( Vec i ) ) edge ( vec_new [( Vec i )] )
    ( vec_push [( Vec i )] edge ( fe 0 0 0 0 ) )
    ( vec_push [( Vec i )] edge ( fe 1 0 0 0 ) )
    ( vec_push [( Vec i )] edge ( fe 2 0 0 0 ) )
    ( vec_push [( Vec i )] edge ( fe 18446744073709551614 4294967295 0 18446744069414584321 ) )
    ( vec_push [( Vec i )] edge ( fe 18446744073709551613 4294967295 0 18446744069414584321 ) )
    ( vec_push [( Vec i )] edge ( fe 18446744073709551615 4294967294 0 18446744069414584321 ) )
    ( vec_push [( Vec i )] edge ( fe 0 0 0 18446744069414584320 ) )
    ( vec_push [( Vec i )] edge ( fe 18446744073709551615 18446744073709551615 18446744073709551615 9223372036854775807 ) )
    ( vec_push [( Vec i )] edge ( fe 0 4294967296 0 0 ) )
    ~ x edge { ~ y edge { = bad + bad ( check scr x y ) = n + n 2 } }
    ( nurl_print `cases: ` ) ( nurl_println_int n )
    ( nurl_print `disagreements: ` ) ( nurl_println_int bad )
    ^ 0
}
