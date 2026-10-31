// rsa16_kernel_agree.nu — std/rsa_mont's 16-limb Montgomery multiply and
// square (RSA-2048's CRT halves) against std/bigint, operation by
// operation. On a CPU with BMI2 + ADX they run the runtime's straight-line
// blocks (nurl_rsa16_mulm_adx / nurl_rsa16_sqrm_adx: every product written
// out, the reduction blocked eight rows at a time); elsewhere, and under
// NURL_CPU_ADX=0, the FIPS kernels — the same golden either way.
//
// For every pair the result r must satisfy r < m and r·2^1024 ≡ a·b
// (mod m). The moduli are the shapes that walk the blocks' carry paths:
// all ones (2^1024 − 1), the top bit alone plus one (2^1023 + 1), all-ones
// low limbs under a lone top bit, 2^1024 − 189, and pseudorandom ones. The
// operands are 0, 1, 2, m − 1, m − 2, the all-ones word pattern reduced
// mod m, and pseudorandom values below m from a fixed seed.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bigint.nu`
$ `stdlib/std/rsa_mont.nu`

: ~ u64 g_rng 0x9e3779b97f4a7c15

@ rnd → u64 {
    = g_rng ^^ g_rng << g_rng 13
    = g_rng ^^ g_rng >> g_rng 7
    = g_rng ^^ g_rng << g_rng 17
    ^ g_rng
}

// 128 big-endian bytes of a BigInt below 2^1024.
@ be128 BigInt x → ( Vec u ) { ^ ( bigint_to_bytes_be x 128 ) }

// 16 little-endian 64-bit limbs of 128 big-endian bytes.
@ limbs ( Vec u ) b → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 16 )
    : ~ i k 0
    ~ < k 16 {
        : ~ u64 acc 0
        : ~ i j 0
        ~ < j 8 {
            : u64 by # u64 ?? ( vec_get [u] b - 127 + * 8 k - 7 j ) { T x → # i x F _ → 0 }
            = acc | << acc 8 by
            = j + j 1
        }
        ( vec_push [i] v # i acc )
        = k + k 1
    }
    ^ v
}

// 128 big-endian bytes of 16 little-endian limbs.
@ bytes_of ( Vec i ) v → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] 128 )
    : ~ i k 15
    ~ >= k 0 {
        : u64 w # u64 ?? ( vec_get [i] v k ) { T x → x F _ → 0 }
        : ~ i sh 56
        ~ >= sh 0 { ( vec_push [u] out # u & # i >> w sh 255 ) = sh - sh 8 }
        = k - k 1
    }
    ^ out
}

@ big_of ( Vec i ) v → BigInt { ^ ( bigint_from_bytes_be ( bytes_of v ) ) }

@ pow2 i bits → BigInt {
    : ( Vec u ) b ( vec_zeroed [u] + 1 / bits 8 )
    ( vec_set [u] b 0 # u << 1 % bits 8 )
    ^ ( bigint_from_bytes_be b )
}

@ bi i x → BigInt { ^ ( bigint_from_i x ) }

// r < m and r·R ≡ a·b (mod m); 1 when not.
@ check BigInt m BigInt big_r BigInt a BigInt b ( Vec i ) r → i {
    : BigInt rb ( big_of r )
    ? >= ( bigint_cmp rb m ) 0 { ^ 1 } {}
    : BigInt lhs ( bigint_rem ( bigint_mul rb big_r ) m )
    : BigInt rhs ( bigint_rem ( bigint_mul a b ) m )
    ^ ? == ( bigint_cmp lhs rhs ) 0 0 1
}

unsafe @ one_modulus s label BigInt m i nrand → i {
    : BigInt big_r ( pow2 1024 )
    : RsaMont c ( _rm_ctx ( be128 m ) )
    : RsaTmp w ( _rm_tmp c )
    // operands: 0, 1, 2, m − 1, m − 2, (2^1024 − 1) mod m, then random
    : ( Vec ( Vec u ) ) ops ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] ops ( be128 ( bi 0 ) ) )
    ( vec_push [( Vec u )] ops ( be128 ( bi 1 ) ) )
    ( vec_push [( Vec u )] ops ( be128 ( bi 2 ) ) )
    ( vec_push [( Vec u )] ops ( be128 ( bigint_sub m ( bi 1 ) ) ) )
    ( vec_push [( Vec u )] ops ( be128 ( bigint_sub m ( bi 2 ) ) ) )
    ( vec_push [( Vec u )] ops ( be128 ( bigint_rem ( bigint_sub big_r ( bi 1 ) ) m ) ) )
    : ~ i k 0
    ~ < k nrand {
        : ( Vec u ) rb ( vec_with_cap [u] 128 )
        : ~ i j 0
        ~ < j 16 {
            : u64 x ( rnd )
            : ~ i sh 56
            ~ >= sh 0 { ( vec_push [u] rb # u & # i >> x sh 255 ) = sh - sh 8 }
            = j + j 1
        }
        ( vec_push [( Vec u )] ops ( be128 ( bigint_rem ( bigint_from_bytes_be rb ) m ) ) )
        = k + k 1
    }
    : i nops ( vec_len [( Vec u )] ops )
    : ( Vec i ) dst ( vec_zeroed [i] 16 )
    : ~ i bad 0
    : ~ i checks 0
    : ~ i x 0
    ~ < x nops {
        : ( Vec u ) ab ?? ( vec_get [( Vec u )] ops x ) { T v → v F _ → ( vec_new [u] ) }
        : ( Vec i ) al ( limbs ab )
        : BigInt abig ( bigint_from_bytes_be ab )
        ( _rm_sqr_d c w dst al )
        = bad + bad ( check m big_r abig abig dst )
        = checks + checks 1
        // every pair among the specials, and each random one with each special
        : ~ i y 0
        ~ < y ? < x 6 nops 6 {
            : ( Vec u ) bb ?? ( vec_get [( Vec u )] ops y ) { T v → v F _ → ( vec_new [u] ) }
            : ( Vec i ) bl ( limbs bb )
            ( _rm_mul_d c w dst al bl )
            = bad + bad ( check m big_r abig ( bigint_from_bytes_be bb ) dst )
            = checks + checks 1
            = y + y 1
        }
        = x + x 1
    }
    ( nurl_print label ) ( nurl_print `: ` ) ( nurl_print_int checks ) ( nurl_print ` products, ` )
    ( nurl_print_int bad ) ( nurl_print ` wrong\n` )
    ^ bad
}

unsafe @ main → i {
    : BigInt big_r ( pow2 1024 )
    : ~ i bad 0
    = bad + bad ( one_modulus `2^1024 - 1` ( bigint_sub big_r ( bi 1 ) ) 40 )
    = bad + bad ( one_modulus `2^1023 + 1` ( bigint_add ( pow2 1023 ) ( bi 1 ) ) 40 )
    = bad + bad ( one_modulus `2^1023 + 2^960 - 1` ( bigint_sub ( bigint_add ( pow2 1023 ) ( pow2 960 ) ) ( bi 1 ) ) 40 )
    = bad + bad ( one_modulus `2^1024 - 189` ( bigint_sub big_r ( bi 189 ) ) 40 )
    : ~ i t 0
    ~ < t 4 {
        : ( Vec u ) mb ( vec_with_cap [u] 128 )
        : ~ i j 0
        ~ < j 16 {
            : u64 x ( rnd )
            : ~ i sh 56
            ~ >= sh 0 { ( vec_push [u] mb # u & # i >> x sh 255 ) = sh - sh 8 }
            = j + j 1
        }
        ( vec_set [u] mb 0 # u | ?? ( vec_get [u] mb 0 ) { T b → # i b F _ → 0 } 128 )
        ( vec_set [u] mb 127 # u | ?? ( vec_get [u] mb 127 ) { T b → # i b F _ → 0 } 1 )
        = bad + bad ( one_modulus `random` ( bigint_from_bytes_be mb ) 60 )
        = t + t 1
    }
    ( nurl_print ? == bad 0 `rsa16 kernels: all agree\n` `rsa16 kernels: MISMATCH\n` )
    ^ ? == bad 0 0 1
}
