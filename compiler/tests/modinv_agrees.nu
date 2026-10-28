// modinv_agrees.nu — the constant-time divstep inverse (std/modinv.nu,
// _modinv256) against the extended Euclid of std/bigint (bigint_modinv)
// for the three moduli the stdlib inverts in: 2^255 − 19, P-256's p and
// P-256's group order n. Inputs: random x < m, and the edge set — 0, 1,
// 2, 3, m − 1, m − 2, (m + 1)/2, each power of two below m at a limb or
// word boundary (2^61 … 2^64, 2^124, 2^186, 2^248 and the top bits), and
// all-ones words below m. 0 has no inverse and gives 0, as both forms
// answer.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bigint.nu`
$ `stdlib/std/modinv.nu`

: ~ u64 g_x 88172645463325252

@ rnd → u64 {
    = g_x ^^ g_x << g_x 13
    = g_x ^^ g_x >> g_x 7
    = g_x ^^ g_x << g_x 17
    ^ g_x
}

// four little-endian words ↔ 32 big-endian bytes
@ be_of u64 w0 u64 w1 u64 w2 u64 w3 → ( Vec u ) {
    : ( Vec u ) o ( vec_new [u] )
    : ~ i k 31
    ~ >= k 0 {
        : u64 w ? < k 8 w0 ? < k 16 w1 ? < k 24 w2 w3
        ( vec_push [u] o # u & >> w # u64 * 8 % k 8 255 )
        = k - k 1
    }
    ^ o
}

@ word_of ( Vec u ) be i j → u64 {
    : ~ u64 w 0
    : ~ i k 7
    ~ >= k 0 {
        = w | << w 8 # u64 ( vec_at [u] be - 31 + * j 8 k )
        = k - k 1
    }
    ^ w
}

// modulus `which` (0: 2^255 − 19, 1: P-256 p, 2: P-256 n) as a BigInt
@ modulus i which → BigInt {
    ? == which 0 { ^ ( bigint_from_bytes_be ( be_of 18446744073709551597 18446744073709551615 18446744073709551615 9223372036854775807 ) ) } {}
    ? == which 1 { ^ ( bigint_from_bytes_be ( be_of 18446744073709551615 4294967295 0 18446744069414584321 ) ) } {}
    ^ ( bigint_from_bytes_be ( be_of 17562291160714782033 13611842547513532036 18446744073709551615 18446744069414584320 ) )
}

// _modinv256 of x (< m) for modulus `which`, as 32 big-endian bytes
@ inv_of i which ( Vec u ) xb → ( Vec u ) {
    : u64 x0 ( word_of xb 0 )
    : u64 x1 ( word_of xb 1 )
    : u64 x2 ( word_of xb 2 )
    : u64 x3 ( word_of xb 3 )
    : ~ u64 o0 0
    : ~ u64 o1 0
    : ~ u64 o2 0
    : ~ u64 o3 0
    ? == which 0 { ( _modinv256 o0 o1 o2 o3 x0 x1 x2 x3 -19 0 0 0 128 4126245384908715493 ) } {}
    ? == which 1 { ( _modinv256 o0 o1 o2 o3 x0 x1 x2 x3 -1 17179869184 0 -274877906880 256 4611686018427387903 ) } {}
    ? == which 2 { ( _modinv256 o0 o1 o2 o3 x0 x1 x2 x3 3727233105432618321 3718823987352861203 4611686018427387899 4611685743549481023 255 3687945983376704433 ) } {}
    ^ ( be_of o0 o1 o2 o3 )
}

@ same ( Vec u ) x ( Vec u ) y → b {
    : ~ i k 0
    ~ < k 32 {
        ? != ( vec_at [u] x k ) ( vec_at [u] y k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// 0 when _modinv256 and bigint_modinv agree on x mod m
@ check i which BigInt x → i {
    : BigInt m ( modulus which )
    : BigInt xr ( bigint_rem x m )
    : ( Vec u ) xb ( bigint_to_bytes_be xr 32 )
    : ( Vec u ) want ( bigint_to_bytes_be ( bigint_modinv xr m ) 32 )
    ? ( same want ( inv_of which xb ) ) { ^ 0 } {}
    ( nurl_print `disagree: modulus ` )
    ( nurl_println_int which )
    ^ 1
}

@ main → i {
    : ~ i bad 0
    : ~ i n 0
    : ~ i which 0
    ~ < which 3 {
        : BigInt m ( modulus which )
        : BigInt one ( bigint_from_i 1 )
        : BigInt two ( bigint_from_i 2 )
        // the edge set
        : ~ i e 0
        ~ < e 4 { = bad + bad ( check which ( bigint_from_i e ) ) = n + n 1 = e + e 1 }
        = bad + bad ( check which ( bigint_sub m one ) )
        = bad + bad ( check which ( bigint_sub m two ) )
        = bad + bad ( check which ( bigint_div ( bigint_add m one ) two ) )
        = n + n 3
        : ( Vec i ) bits ( vec_new [i] )
        ( vec_push [i] bits 61 ) ( vec_push [i] bits 62 ) ( vec_push [i] bits 63 ) ( vec_push [i] bits 64 )
        ( vec_push [i] bits 124 ) ( vec_push [i] bits 186 ) ( vec_push [i] bits 248 )
        ( vec_push [i] bits 253 ) ( vec_push [i] bits 254 ) ( vec_push [i] bits 255 )
        : ~ i b 0
        ~ < b ( vec_len [i] bits ) {
            : i k ( vec_at [i] bits b )
            : u64 w << # u64 1 # u64 % k 64
            : i q / k 64
            : BigInt pk ( bigint_from_bytes_be ( be_of ? == q 0 w 0 ? == q 1 w 0 ? == q 2 w 0 ? == q 3 w 0 ) )
            ? < ( bigint_cmp pk m ) 0 { = bad + bad ( check which pk ) = n + n 1 } {}
            = b + b 1
        }
        : BigInt ones ( bigint_from_bytes_be ( be_of 18446744073709551615 18446744073709551615 18446744073709551615 4611686018427387903 ) )
        = bad + bad ( check which ones )
        = n + n 1
        // random x
        : ~ i r 0
        ~ < r 400 {
            = bad + bad ( check which ( bigint_from_bytes_be ( be_of ( rnd ) ( rnd ) ( rnd ) ( rnd ) ) ) )
            = n + n 1
            = r + r 1
        }
        = which + which 1
    }
    ( nurl_print `cases ` )
    ( nurl_println_int n )
    ( nurl_print `disagreements ` )
    ( nurl_println_int bad )
    ^ 0
}
