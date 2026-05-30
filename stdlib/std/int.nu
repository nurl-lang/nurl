// stdlib/std/int.nu — integer helpers (signed 64-bit)
//
//   ( int_abs n )         → i        absolute value (LLONG_MIN saturates)
//   ( int_pow x y )       → i        x^y for y ≥ 0; returns 0 when y < 0
//                                    (use float_pow for fractional/negative)
//   ( int_sign n )        → i        -1 / 0 / +1
//   ( int_gcd a b )       → i        greatest common divisor (non-negative)
//   ( int_lcm a b )       → i        least common multiple (non-negative)
//   ( int_isqrt n )       → i        floor(sqrt n); negative n → 0
//   ( int_parse s )       → ! i ParseErr   strict decimal parse from raw s
//                                          - empty / sign-only        → Empty
//                                          - non-digit byte           → BadFormat
//                                          (overflow not detected; atoll wraps —
//                                           future revision may add Overflow)
//   ( int_min/max/clamp ) — see stdlib/std/cmp.nu (`min_i`/`max_i`/`clamp_i`)
//
// Constants:
//   INT_MAX   =  9223372036854775807
//   ( int_min ) → -9223372036854775808 (computed; literal would overflow
//                                       since the lexer parses `-N` as
//                                       `- 0 N` and N must fit in i64)

$ `stdlib/core/errors.nu`
$ `stdlib/core/char.nu`
$ `stdlib/core/string.nu`

// ── Constants ──────────────────────────────────────────────────────

: i INT_MAX 9223372036854775807

// Two's-complement minimum. The bare literal -9223372036854775808 cannot
// be lexed (its magnitude overflows a positive i64 before the sign is
// applied), but compile-time const folding evaluates the subtraction.
: i INT_MIN - -9223372036854775807 1

// Retained for source compatibility — predates const folding, when a
// module-level `: i FOO <expr>` accepted only a literal RHS. New code
// should prefer the `INT_MIN` constant above.
@ int_min_val → i {
    ^ INT_MIN
}

// ── Operations ─────────────────────────────────────────────────────

// LLONG_MIN (`- -9223372036854775807 1`) is its own negation in
// two's-complement; the saturate-to-LLONG_MIN match prevents the
// wrap to +0.
@ int_abs i n → i {
    ? == n - -9223372036854775807 1 { ^ n } {}
    ? < n 0 { ^ - 0 n } {}
    ^ n
}

// Exponentiation-by-squaring; non-negative `y` only. Negative `y`
// returns 0 (use `float_pow` for fractional / negative exponents).
@ int_pow i x i y → i {
    ? < y 0 { ^ 0 } {}
    : ~ i r 1
    : ~ i b x
    : ~ i e y
    ~ > e 0 {
        ? != 0 & e 1 { = r * r b } {}
        = e >> e 1
        ? > e 0 { = b * b b } {}
    }
    ^ r
}

@ int_sign i n → i {
    ? < n 0 { ^ -1 } {}
    ? > n 0 { ^ 1 } {}
    ^ 0
}

// Greatest common divisor via the Euclidean algorithm. Operates on the
// magnitudes, so the result is always non-negative; `gcd(0, 0)` is 0 and
// `gcd(0, n)` is `|n|`.
@ int_gcd i a i b → i {
    : ~ i x ( int_abs a )
    : ~ i y ( int_abs b )
    ~ != y 0 {
        : i t % x y
        = x y
        = y t
    }
    ^ x
}

// Least common multiple. Non-negative; `lcm(0, n)` is 0. Computed as
// `|a| / gcd * |b|` (divide first to reduce overflow pressure); the
// product can still overflow for large inputs — caller's responsibility.
@ int_lcm i a i b → i {
    ? | == a 0 == b 0 { ^ 0 } {}
    : i g ( int_gcd a b )
    ^ * / ( int_abs a ) g ( int_abs b )
}

// Integer (floor) square root via Newton's method: the largest `r` with
// `r*r <= n`. Negative `n` returns 0. Exact — no float round-off.
@ int_isqrt i n → i {
    ? <= n 0 { ^ 0 } {}
    : ~ i x n
    : ~ i y >> + x 1 1
    ~ < y x {
        = x y
        = y >> + x / n x 1
    }
    ^ x
}

// Strict decimal parse from raw `s`. Accepts optional leading '-' or '+'
// followed by one or more decimal digits and nothing else. Mirrors
// `string_to_int` (which takes an owned String) but accepts a raw `i8*`
// directly, matching `float_parse`'s shape so CLI args / env vars can be
// parsed without a String round-trip.
@ int_parse s str → !i ParseErr {
    : i len ( nurl_str_len str )
    ? == len 0 { ^ @ !i ParseErr { F @ ParseErr { Empty } } } {}

    : ~ i idx 0
    : i first ( nurl_str_get str 0 )
    // '-' = 45, '+' = 43
    ? | == first 45 == first 43 { = idx 1 } {}

    // bare sign with no digits
    ? == idx len { ^ @ !i ParseErr { F @ ParseErr { Empty } } } {}

    ~ < idx len {
        : i c ( nurl_str_get str idx )
        ? == ( is_digit c ) 0 {
            ^ @ !i ParseErr { F @ ParseErr { BadFormat } }
        } {}
        = idx + idx 1
    }

    ^ @ !i ParseErr { T ( nurl_str_to_int str ) }
}
