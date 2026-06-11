// Test: stdlib/std/float.nu + stdlib/std/int.nu
//
// Covers the libm wrappers (sqrt/sin/cos/log/exp/pow/floor/ceil/round),
// integer abs/pow/sign, NaN/Inf predicates, and the strict float parser.
// Float results are rounded to integers (or compared by sign / threshold)
// to keep stdout byte-deterministic across libm implementations.

$ `stdlib/core/errors.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/int.nu`

@ pi i n s label → v {
    ( nurl_print label ) ( nurl_print `=` )
    ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
}

@ pb b v s label → v {
    ( nurl_print label ) ( nurl_print `=` )
    ( nurl_print ? v `T` `F` ) ( nurl_print `\n` )
}

@ main → i {
    // ── Integer helpers ────────────────────────────────────
    ( pi ( int_abs -7 ) `int_abs(-7)` )
    ( pi ( int_abs 5 ) `int_abs(5)` )
    ( pi ( int_pow 2 10 ) `int_pow(2,10)` )
    ( pi ( int_pow 3 4 ) `int_pow(3,4)` )
    ( pi ( int_pow 5 0 ) `int_pow(5,0)` )  // anything^0 = 1
    ( pi ( int_pow 7 -2 ) `int_pow(7,-2)` )  // negative y → 0
    ( pi ( int_sign -42 ) `int_sign(-42)` )
    ( pi ( int_sign 0 ) `int_sign(0)` )
    ( pi ( int_sign 99 ) `int_sign(99)` )
    ( pi INT_MAX `INT_MAX` )
    ( pi ( int_min_val ) `INT_MIN` )

    // ── Float wrappers — rounded to int for portability ────
    ( pi # i ( float_sqrt 16.0 ) `sqrt(16)` )  // 4
    ( pi # i ( float_sqrt 2.0 ) `sqrt(2)_t` )  // 1 (truncates)
    ( pi # i ( float_floor 3.7 ) `floor(3.7)` )  // 3
    ( pi # i ( float_ceil 3.2 ) `ceil(3.2)` )  // 4
    ( pi # i ( float_round 2.5 ) `round(2.5)` )  // 3 (away-zero)
    ( pi # i ( float_round -2.5 ) `round(-2.5)` )  // -3
    ( pi # i ( float_abs -8.5 ) `abs(-8.5)_t` )  // 8 (truncates)
    ( pi # i ( float_pow 2.0 8.0 ) `pow(2,8)` )  // 256
    ( pi # i ( float_pow 4.0 0.5 ) `pow(4,0.5)` )  // 2  (sqrt via pow)
    ( pi # i ( float_exp 0.0 ) `exp(0)` )  // 1
    ( pi # i ( float_log 1.0 ) `log(1)` )  // 0

    // sin(0)=0, cos(0)=1, tan(0)=0
    ( pi # i ( float_sin 0.0 ) `sin(0)` )
    ( pi # i ( float_cos 0.0 ) `cos(0)` )
    ( pi # i ( float_tan 0.0 ) `tan(0)` )

    // sin(π/2) ≈ 1, cos(π) ≈ -1
    ( pi # i ( float_round ( float_sin PI_2 ) ) `sin(π/2)` )  // 1
    ( pi # i ( float_round ( float_cos PI ) ) `cos(π)` )  // -1

    // atan2(1,0) = π/2 ; atan2(0,-1) = π
    ( pi # i ( float_round ( float_atan2 1.0 0.0 ) ) `atan2(1,0)_r` )  // 2 (round 1.5708)
    ( pi # i ( float_round ( float_atan2 0.0 -1.0 ) ) `atan2(0,-1)_r` )  // 3 (round π=3.14159)

    // log(e) = 1
    ( pi # i ( float_log E ) `log(e)` )

    // ── Predicates ────────────────────────────────────────
    // 0/0-style NaN via log(-1).
    ( pb ( float_is_nan ( float_log -1.0 ) ) `is_nan(log(-1))` )
    ( pb ( float_is_nan 1.0 ) `is_nan(1)` )
    // exp(1000) overflows to +Inf in IEEE-754 doubles.
    ( pb ( float_is_inf ( float_exp 1000.0 ) ) `is_inf(exp1000)` )
    ( pb ( float_is_inf 1.0 ) `is_inf(1)` )

    // ── float_parse strict ────────────────────────────────
    : !f ParseErr p1 ( float_parse `3.14` )
    ?? p1 {
        T x → { ( pi # i x `parse(3.14)_t` ) }  // 3 (truncates)
        F e → { ( nurl_print `parse(3.14)_err\n` ) }
    }
    : !f ParseErr p2 ( float_parse `` )
    ?? p2 {
        T x → { ( nurl_print `parse(empty)_unexpected_ok\n` ) }
        F e → { ( nurl_print `parse(empty)=` )
            ( nurl_print ( parse_err_msg # ParseErr e ) )
            ( nurl_print `\n` ) }
    }
    : !f ParseErr p3 ( float_parse `1.5xyz` )
    ?? p3 {
        T x → { ( nurl_print `parse(garbage)_unexpected_ok\n` ) }
        F e → { ( nurl_print `parse(garbage)=` )
            ( nurl_print ( parse_err_msg # ParseErr e ) )
            ( nurl_print `\n` ) }
    }
    : !f ParseErr p4 ( float_parse `-1.5e2` )
    ?? p4 {
        T x → { ( pi # i x `parse(-1.5e2)` ) }  // -150
        F e → { ( nurl_print `parse(-1.5e2)_err\n` ) }
    }

    ( nurl_print `done\n` )
    ^ 0
}
