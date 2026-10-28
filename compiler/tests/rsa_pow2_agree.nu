// rsa_pow2_agree.nu — std/rsa_mont's _rm_pow2_ct, the two powers of a
// CRT signature, against std/bigint's bigint_modpow. On a CPU with
// AVX-512 IFMA two 1024-bit moduli take __rm_pow2_52: both powers at
// once in radix 2^52, the almost Montgomery multiply on
// nurl_v256_madd52lo / _hi; crypto_tier_ir.sh runs this again with
// NURL_CPU_IFMA=0, and on any other CPU the powers run one after the
// other on _rm_pow_ct — one output for all of them.
//
// Pairs of two different 1024-bit moduli, of one modulus twice, and of
// a 1024-bit and a 960-bit one (which no CPU runs at once). Bases are
// 0, 1, m − 1 and pseudorandom below m — each half its own — and the
// exponents 17 pseudorandom limbs, the width of a blinded CRT exponent;
// moduli, bases and exponents from a fixed seed.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bigint.nu`
$ `stdlib/std/rsa_mont.nu`

: ~ u64 g_rng 0x9e3779b97f4a7c15

@ rnd_byte → i {
    = g_rng ^^ g_rng << g_rng 13
    = g_rng ^^ g_rng >> g_rng 7
    = g_rng ^^ g_rng << g_rng 17
    ^ # i & g_rng 255
}

@ rnd_bytes i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u ( rnd_byte ) ) = k + k 1 }
    ^ v
}

// An odd modulus of exactly nb bytes, its top bit set.
@ modulus i nb → ( Vec u ) {
    : ( Vec u ) n ( rnd_bytes nb )
    ( vec_set [u] n 0 # u | ?? ( vec_get [u] n 0 ) { T b → # i b F _ → 0 } 128 )
    ( vec_set [u] n - nb 1 # u | ?? ( vec_get [u] n - nb 1 ) { T b → # i b F _ → 0 } 1 )
    ^ n
}

// Base number `kind` below modulus n (big-endian): 0, 1, n − 1, random.
@ base_of ( Vec u ) n i kind → ( Vec u ) {
    : i nb ( vec_len [u] n )
    ? == kind 0 { ^ ( vec_zeroed [u] 1 ) } {}
    ? == kind 1 { : ( Vec u ) v ( vec_zeroed [u] 1 ) ( vec_set [u] v 0 # u 1 ) ^ v } {}
    ? == kind 2 {
        : ( Vec u ) v ( bytes_slice n 0 nb )
        ( vec_set [u] v - nb 1 # u - ?? ( vec_get [u] v - nb 1 ) { T b → # i b F _ → 1 } 1 )
        ^ v
    } {}
    ^ ( rnd_bytes - nb 1 )
}

// Big-endian bytes → n little-endian 64-bit limbs, and back to k bytes.
@ limbs ( Vec u ) b i n → ( Vec i ) {
    : ( Vec i ) v ( vec_zeroed [i] n )
    : i len ( vec_len [u] b )
    : ~ i k 0
    ~ < k len {
        : i at >> k 3
        ? < at n {
            : u64 by # u64 ?? ( vec_get [u] b - - len 1 k ) { T x → # i x F _ → 0 }
            : i cur ?? ( vec_get [i] v at ) { T x → x F _ → 0 }
            ( vec_set [i] v at | cur # i << by # u64 * & k 7 8 )
        } {}
        = k + k 1
    }
    ^ v
}

@ bytes_of ( Vec i ) v i k → ( Vec u ) {
    : ( Vec u ) out ( vec_zeroed [u] k )
    : ~ i j 0
    ~ < j k {
        : u64 w # u64 ?? ( vec_get [i] v >> j 3 ) { T x → x F _ → 0 }
        ( vec_set [u] out - - k 1 j # u & >> w # u64 * & j 7 8 255 )
        = j + j 1
    }
    ^ out
}

@ want ( Vec u ) x ( Vec u ) e ( Vec u ) n → ( Vec u ) {
    ^ ( bigint_to_bytes_be ( bigint_modpow ( bigint_from_bytes_be x ) ( bigint_from_bytes_be e ) ( bigint_from_bytes_be n ) ) ( vec_len [u] n ) )
}

// _rm_pow2_ct is `raw`: it trusts its residues to hold their context's
// n limbs. main builds them that way (`limbs x . c n`, 17 exponent
// limbs, o1 and o2 of . c n), so this is where the test vouches for it.
unsafe @ pow2 RsaMont c1 RsaTmp w1 ( Vec i ) x1 ( Vec i ) e1 RsaMont c2 RsaTmp w2 ( Vec i ) x2 ( Vec i ) e2 ( Vec i ) o1 ( Vec i ) o2 → v {
    ( _rm_pow2_ct c1 w1 x1 e1 17 c2 w2 x2 e2 17 o1 o2 )
}

@ main → i {
    : ~ i bad 0
    : ~ i pair 0
    ~ < pair 3 {
        : ( Vec u ) n1 ( modulus 128 )
        : ( Vec u ) n2 ? == pair 1 ( bytes_slice n1 0 128 ) ( modulus ? == pair 2 120 128 )
        : RsaMont c1 ( _rm_ctx n1 )
        : RsaMont c2 ( _rm_ctx n2 )
        : RsaTmp w1 ( _rm_tmp c1 )
        : RsaTmp w2 ( _rm_tmp c2 )
        : ~ i ok 0
        : ~ i trial 0
        ~ < trial 8 {
            : ( Vec u ) x1 ( base_of n1 % trial 4 )
            : ( Vec u ) x2 ( base_of n2 % + trial 1 4 )
            : ( Vec u ) e1 ( rnd_bytes 136 )
            : ( Vec u ) e2 ( rnd_bytes 136 )
            : ( Vec i ) o1 ( vec_zeroed [i] . c1 n )
            : ( Vec i ) o2 ( vec_zeroed [i] . c2 n )
            ( pow2 c1 w1 ( limbs x1 . c1 n ) ( limbs e1 17 ) c2 w2 ( limbs x2 . c2 n ) ( limbs e2 17 ) o1 o2 )
            : b g1 ( bytes_eq ( bytes_of o1 ( vec_len [u] n1 ) ) ( want x1 e1 n1 ) )
            : b g2 ( bytes_eq ( bytes_of o2 ( vec_len [u] n2 ) ) ( want x2 e2 n2 ) )
            ? & g1 g2 { = ok + ok 1 } {
                ( nurl_print `MISMATCH pair=` ) ( nurl_print_int pair )
                ( nurl_print ` trial=` ) ( nurl_print_int trial ) ( nurl_print `\n` )
                = bad + bad 1
            }
            = trial + trial 1
        }
        ( nurl_print `pair ` ) ( nurl_print_int pair ) ( nurl_print ` (` )
        ( nurl_print_int . c1 n ) ( nurl_print ` and ` ) ( nurl_print_int . c2 n )
        ( nurl_print ` limbs): ` ) ( nurl_print_int ok ) ( nurl_print ` of 8 agree with bigint_modpow\n` )
        = pair + pair 1
    }
    ^ ? == bad 0 0 1
}
