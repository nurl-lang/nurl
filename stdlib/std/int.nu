// stdlib/std/int.nu — integer helpers (signed 64-bit)
//
//   ( int_abs n )         → i        absolute value (LLONG_MIN saturates)
//   ( int_pow x y )       → i        x^y for y ≥ 0; returns 0 when y < 0
//                                    (use float_pow for fractional/negative)
//   ( int_sign n )        → i        -1 / 0 / +1
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

// ── Constants ──────────────────────────────────────────────────────

: i INT_MAX 9223372036854775807

// Module-level `: i FOO <expr>` only accepts literal RHS, so INT_MIN is
// exposed as a niladic function that evaluates the two's-complement
// minimum at call time.
@ int_min_val → i {
    ^ - -9223372036854775807 1
}

// ── Operations ─────────────────────────────────────────────────────

@ int_abs i n → i {
    ^ ( nurl_iabs n )
}

@ int_pow i x i y → i {
    ^ ( nurl_ipow x y )
}

@ int_sign i n → i {
    ? < n 0 { ^ -1 } {}
    ? > n 0 { ^ 1 } {}
    ^ 0
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
