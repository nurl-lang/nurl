// float_extra.nu — offline acceptance test for the libm wrappers added
// to stdlib/std/float.nu (trunc / cbrt / hypot / log2 / log10 / sign /
// erf / erfc).
//
// Compares against expected values with a 1e-9 epsilon and prints only
// the ok/MISMATCH verdict, so the baseline is independent of any
// platform float-formatting differences. Determinism: pure math.

$ `stdlib/std/float.nu`

@ feq f a f b → b {
    ^ < ( float_abs - a b ) 0.000000001
}

@ ck s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok ` ok\n` ` MISMATCH!\n` )
}

@ main → i {
    ( ck `trunc(2.7)    ` ( feq ( float_trunc 2.7 ) 2.0 ) )
    ( ck `trunc(-2.7)   ` ( feq ( float_trunc -2.7 ) -2.0 ) )

    ( ck `cbrt(8)       ` ( feq ( float_cbrt 8.0 ) 2.0 ) )
    ( ck `cbrt(-27)     ` ( feq ( float_cbrt -27.0 ) -3.0 ) )
    // erf: odd, erf(0)=0, and the two textbook values
    ( ck `erf(0)        ` ( feq ( float_erf 0.0 ) 0.0 ) )
    ( ck `erf(1)        ` ( feq ( float_erf 1.0 ) 0.8427007929497149 ) )
    ( ck `erf(-1)       ` ( feq ( float_erf -1.0 ) -0.8427007929497149 ) )
    ( ck `erfc(1)       ` ( feq ( float_erfc 1.0 ) 0.15729920705028513 ) )
    // erfc is not `1 - erf` in disguise: at x = 10 the subtraction has
    // cancelled to exactly 0.0, while erfc still resolves 2.1e-45.
    ( ck `1-erf(10)==0  ` == - 1.0 ( float_erf 10.0 ) 0.0 )
    ( ck `erfc(10)>0    ` > ( float_erfc 10.0 ) 0.0 )
    ( ck `erfc(10) mag  ` < ( float_erfc 10.0 ) 0.000000000000000000000000000000000000000001 )

    ( ck `hypot(3,4)    ` ( feq ( float_hypot 3.0 4.0 ) 5.0 ) )
    ( ck `hypot(0,0)    ` ( feq ( float_hypot 0.0 0.0 ) 0.0 ) )

    ( ck `log2(8)       ` ( feq ( float_log2 8.0 ) 3.0 ) )
    ( ck `log2(1)       ` ( feq ( float_log2 1.0 ) 0.0 ) )

    ( ck `log10(1000)   ` ( feq ( float_log10 1000.0 ) 3.0 ) )
    ( ck `log10(1)      ` ( feq ( float_log10 1.0 ) 0.0 ) )

    ( ck `sign(-5.5)    ` ( feq ( float_sign -5.5 ) -1.0 ) )
    ( ck `sign(5.5)     ` ( feq ( float_sign 5.5 ) 1.0 ) )
    ( ck `sign(0.0)     ` ( feq ( float_sign 0.0 ) 0.0 ) )

    ^ 0
}
