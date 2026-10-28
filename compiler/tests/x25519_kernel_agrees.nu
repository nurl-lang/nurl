// x25519_kernel_agrees.nu — the X25519 field kernels (the compiler's
// nurl_x25519_mulm / nurl_x25519_sqrm, the ADX tier) agree with the
// register form (__f4_mul_in) on every input tried, and the ladder and
// the fixed-base walk written on them (__scalarmult_k, __xe_base_k) with
// the register ones (__scalarmult_r, __xe_base_r).
//
// Elements are any 256-bit pattern (the lazy form), so the inputs are
// random words, the edge set — 0, 1, 19, 38, p − 1, p, p + 1, 2^255 − 1,
// 2^255, 2^256 − 39, 2^256 − 38, 2^256 − 1 — every pair of it, and the
// result written over an operand. Results are compared reduced. The
// ladders are compared on random scalars against the edge points (u ≥ p
// and the top bit set among them, 0 and 1 low-order) and random points,
// x25519 itself against the register ladder, and the fixed-base walks
// (__xe_base_k, __xe_base_r, x25519_base) against the ladder at u = 9.
// Without the tier (NURL_CPU_ADX=0, or off x86-64) the kernel side is
// the register form too, and the test still holds; crypto_tier_ir.sh
// runs it both ways.

$ `stdlib/core/vec.nu`
$ `stdlib/std/x25519.nu`

: ~ u64 g_x 88172645463325252

@ rnd → u64 {
    = g_x ^^ g_x << g_x 13
    = g_x ^^ g_x >> g_x 7
    = g_x ^^ g_x << g_x 17
    ^ g_x
}

@ push_word ( Vec u ) v u64 w → v {
    : ~ u64 sh 0
    ~ < sh 64 {
        ( vec_push [u] v # u & >> w sh 255 )
        = sh + sh 8
    }
}

@ fe u64 a u64 b u64 c u64 d → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( push_word v a ) ( push_word v b ) ( push_word v c ) ( push_word v d )
    ^ v
}

// Edge element k of 12.
@ edge i k → ( Vec u ) {
    : u64 m 18446744073709551615
    : u64 h 9223372036854775807
    ? == k 0 { ^ ( fe 0 0 0 0 ) } {}
    ? == k 1 { ^ ( fe 1 0 0 0 ) } {}
    ? == k 2 { ^ ( fe 19 0 0 0 ) } {}
    ? == k 3 { ^ ( fe 38 0 0 0 ) } {}
    ? == k 4 { ^ ( fe - m 19 m m h ) } {}
    ? == k 5 { ^ ( fe - m 18 m m h ) } {}
    ? == k 6 { ^ ( fe - m 17 m m h ) } {}
    ? == k 7 { ^ ( fe m m m h ) } {}
    ? == k 8 { ^ ( fe 0 0 0 + h 1 ) } {}
    ? == k 9 { ^ ( fe - m 38 m m m ) } {}
    ? == k 10 { ^ ( fe - m 37 m m m ) } {}
    ^ ( fe m m m m )
}

@ same ( Vec u ) x ( Vec u ) y → b {
    : ~ i k 0
    ~ < k 32 {
        ? != ( vec_at [u] x k ) ( vec_at [u] y k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// a·b, a·b over a, a² and a² over a: the kernels against the register form.
@ check ( Vec u ) a ( Vec u ) b → i {
    : ( Vec u ) want ( _x25519_mul_r a b )
    : ( Vec u ) sq ( _x25519_mul_r a a )
    : ~ i bad 0
    ? ( same want ( _x25519_mul_k a b F ) ) {} { = bad + bad 1 }
    ? ( same want ( _x25519_mul_k a b T ) ) {} { = bad + bad 1 }
    ? ( same sq ( _x25519_sq_k a F ) ) {} { = bad + bad 1 }
    ? ( same sq ( _x25519_sq_k a T ) ) {} { = bad + bad 1 }
    ^ bad
}

@ main → i {
    : ~ i bad 0
    : ~ i n 0
    : ~ i k 0
    ~ < k 30000 {
        = bad + bad ( check ( fe ( rnd ) ( rnd ) ( rnd ) ( rnd ) ) ( fe ( rnd ) ( rnd ) ( rnd ) ( rnd ) ) )
        = n + n 4
        = k + k 1
    }
    : ~ i i 0
    ~ < i 12 {
        : ~ i j 0
        ~ < j 12 {
            = bad + bad ( check ( edge i ) ( edge j ) )
            = n + n 4
            = j + j 1
        }
        = i + i 1
    }
    ( nurl_print `field cases ` )
    ( nurl_println_int n )
    ( nurl_print `field disagreements ` )
    ( nurl_println_int bad )

    : ~ i lb 0
    : ~ i ln 0
    = k 0
    ~ < k 36 {
        : ( Vec u ) sc ( fe ( rnd ) ( rnd ) ( rnd ) ( rnd ) )
        : ( Vec u ) pt ? < k 12 ( edge k ) ( fe ( rnd ) ( rnd ) ( rnd ) ( rnd ) )
        : ( Vec u ) want ( _x25519_ladder_r sc pt )
        ? ( same want ( _x25519_ladder_k sc pt ) ) {} { = lb + lb 1 }
        ? ( same want ( x25519 sc pt ) ) {} { = lb + lb 1 }
        = ln + ln 2
        = k + k 1
    }
    // the fixed-base walks, and both against the ladder at u = 9
    : ( Vec u ) nine ( fe 9 0 0 0 )
    = k 0
    ~ < k 24 {
        : ( Vec u ) sc ( fe ( rnd ) ( rnd ) ( rnd ) ( rnd ) )
        : ( Vec u ) want ( _x25519_ladder_r sc nine )
        ? ( same want ( _x25519_base_r sc ) ) {} { = lb + lb 1 }
        ? ( same want ( _x25519_base_k sc ) ) {} { = lb + lb 1 }
        ? ( same want ( x25519_base sc ) ) {} { = lb + lb 1 }
        = ln + ln 3
        = k + k 1
    }
    ( nurl_print `ladder cases ` )
    ( nurl_println_int ln )
    ( nurl_print `ladder disagreements ` )
    ( nurl_println_int lb )
    ^ 0
}
