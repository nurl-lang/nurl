// int_extra.nu — offline acceptance test for the number-theory helpers
// added to stdlib/std/int.nu (int_gcd / int_lcm / int_isqrt).
//
// Determinism: pure arithmetic, no clock/socket/env. ASan-clean.

$ `stdlib/std/int.nu`

@ ck s label i got i want → v {
    ( nurl_print label )
    ( nurl_print ` = ` )
    ( nurl_println_int got )
    ( nurl_print ? == got want ` ok\n` ` MISMATCH!\n` )
}

@ main → i {
    // gcd
    ( ck `gcd(12,18)  ` ( int_gcd 12 18 ) 6 )
    ( ck `gcd(-12,18) ` ( int_gcd -12 18 ) 6 )
    ( ck `gcd(0,0)    ` ( int_gcd 0 0 ) 0 )
    ( ck `gcd(0,7)    ` ( int_gcd 0 7 ) 7 )
    ( ck `gcd(17,5)   ` ( int_gcd 17 5 ) 1 )

    // lcm
    ( ck `lcm(4,6)    ` ( int_lcm 4 6 ) 12 )
    ( ck `lcm(0,5)    ` ( int_lcm 0 5 ) 0 )
    ( ck `lcm(-4,6)   ` ( int_lcm -4 6 ) 12 )
    ( ck `lcm(21,6)   ` ( int_lcm 21 6 ) 42 )

    // isqrt
    ( ck `isqrt(0)    ` ( int_isqrt 0 ) 0 )
    ( ck `isqrt(1)    ` ( int_isqrt 1 ) 1 )
    ( ck `isqrt(4)    ` ( int_isqrt 4 ) 2 )
    ( ck `isqrt(8)    ` ( int_isqrt 8 ) 2 )
    ( ck `isqrt(9)    ` ( int_isqrt 9 ) 3 )
    ( ck `isqrt(15)   ` ( int_isqrt 15 ) 3 )
    ( ck `isqrt(16)   ` ( int_isqrt 16 ) 4 )
    ( ck `isqrt(99)   ` ( int_isqrt 99 ) 9 )
    ( ck `isqrt(10000)` ( int_isqrt 10000 ) 100 )
    ( ck `isqrt(-5)   ` ( int_isqrt -5 ) 0 )

    ^ 0
}
