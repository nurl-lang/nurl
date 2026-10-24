// rsa_mont_kernels.nu — std/rsa_mont's Montgomery kernels against an
// independent reference: m^d mod n by _rsa_private (a plain exponent: the
// constant-time fixed-window exponentiation, every step a Montgomery
// square or multiply) checked against std/bigint's bigint_modpow, for
// moduli of 15, 16, 17, 24 and 32 limbs. 16 limbs — RSA-2048's CRT
// halves — run the generated straight-line kernels (__rm_mul16 /
// __rm_sqr16); the other widths the generic FIPS kernels either side of
// them. Bases include 0, 1 and n − 1; the moduli, bases and exponents
// are otherwise pseudorandom from a fixed seed, so a wrong limb anywhere
// in a kernel shows as a mismatch, and the run is reproducible.

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

@ one → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 1 )
    ^ v
}

// The low bytes of x − 1 for an odd x (a base of n − 1).
@ minus1 ( Vec u ) x → ( Vec u ) {
    : ( Vec u ) v ( bytes_slice x 0 ( vec_len [u] x ) )
    : i last - ( vec_len [u] v ) 1
    ( vec_set [u] v last # u - ?? ( vec_get [u] v last ) { T b → # i b F _ → 1 } 1 )
    ^ v
}

@ main → i {
    : ( Vec i ) widths ( vec_new [i] )
    ( vec_push [i] widths 15 )
    ( vec_push [i] widths 16 )
    ( vec_push [i] widths 17 )
    ( vec_push [i] widths 24 )
    ( vec_push [i] widths 32 )
    : ( Vec u ) e ( vec_new [u] )
    ( vec_push [u] e # u 1 ) ( vec_push [u] e # u 0 ) ( vec_push [u] e # u 1 )
    : ~ i bad 0
    : ~ i w 0
    ~ < w ( vec_len [i] widths ) {
        : i nl ?? ( vec_get [i] widths w ) { T x → x F _ → 16 }
        : i nb * nl 8
        : ~ i ok 0
        : ~ i trial 0
        ~ < trial 3 {
            // an odd modulus of exactly nb bytes
            : ( Vec u ) n ( rnd_bytes nb )
            ( vec_set [u] n 0 # u | ?? ( vec_get [u] n 0 ) { T b → # i b F _ → 0 } 128 )
            ( vec_set [u] n - nb 1 # u | ?? ( vec_get [u] n - nb 1 ) { T b → # i b F _ → 0 } 1 )
            : BigInt nbig ( bigint_from_bytes_be n )
            : ~ i case 0
            ~ < case 5 {
                // base: 0, 1, n − 1, then pseudorandom below n
                : ( Vec u ) m ? == case 0 ( vec_zeroed [u] 1 ) ? == case 1 ( one ) ? == case 2 ( minus1 n ) ( rnd_bytes - nb 1 )
                // exponent: up to the modulus width, first byte non-zero
                : ( Vec u ) d ( rnd_bytes - nb * 3 case )
                ( vec_set [u] d 0 # u | ?? ( vec_get [u] d 0 ) { T b → # i b F _ → 0 } 1 )
                : ( Vec u ) got ( _rsa_private n e d m nb )
                : ( Vec u ) want ( bigint_to_bytes_be ( bigint_modpow ( bigint_from_bytes_be m ) ( bigint_from_bytes_be d ) nbig ) nb )
                ? ( bytes_eq got want ) { = ok + ok 1 } {
                    ( nurl_print `MISMATCH limbs=` ) ( nurl_print_int nl )
                    ( nurl_print ` trial=` ) ( nurl_print_int trial ) ( nurl_print ` case=` ) ( nurl_print_int case ) ( nurl_print `\n` )
                    = bad + bad 1
                }
                = case + case 1
            }
            = trial + trial 1
        }
        ( nurl_print `limbs ` ) ( nurl_print_int nl ) ( nurl_print `: ` ) ( nurl_print_int ok ) ( nurl_print ` of 15 agree with bigint_modpow\n` )
        = w + w 1
    }
    ^ ? == bad 0 0 1
}
