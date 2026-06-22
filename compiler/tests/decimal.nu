// decimal.nu — std/decimal.nu acceptance: exact fixed-point arithmetic,
// banker's rounding, division with explicit scale, parse/format, compare.

$ `stdlib/core/string.nu`
$ `stdlib/std/decimal.nu`

// parse "s", print its canonical form
@ pp s label s in → v {
    ( nurl_print label ) ( nurl_print `: ` )
    : !Decimal ParseErr r ( dec_from_string in )
    ?? r {
        T d → { : String s ( dec_to_string d ) ( nurl_print ( string_data s ) ) ( string_free s ) ( dec_free d ) }
        F _ → ( nurl_print `PARSE_ERR` )
    }
    ( nurl_print `\n` )
}

@ pd Decimal d → v { : String s ( dec_to_string d ) ( nurl_print ( string_data s ) ) ( string_free s ) }

@ mk s in → Decimal {
    : !Decimal ParseErr r ( dec_from_string in )
    ^ ?? r { T d → d F _ → ( dec_zero ) }
}

@ main → i {
    // ── parse + round-trip ──
    ( pp `int` `42` )
    ( pp `neg` `-12.340` )
    ( pp `lt1` `.5` )
    ( pp `negfrac` `-.001` )
    ( pp `trailing_dot` `7.` )
    ( pp `bad` `1.2.3` )
    ( pp `empty` `` )
    ( pp `garbage` `12x` )

    // ── the canonical float failure: 0.1 + 0.2 == 0.3 exactly ──
    : Decimal a ( mk `0.1` )
    : Decimal b ( mk `0.2` )
    : Decimal sum ( dec_add a b )
    ( nurl_print `0.1+0.2=` ) ( pd sum )
    : Decimal three ( mk `0.3` )
    ( nurl_print ` ==0.3? ` ) ( nurl_print ? == 0 ( dec_cmp sum three ) `T` `F` ) ( nurl_print `\n` )
    ( dec_free a ) ( dec_free b ) ( dec_free sum ) ( dec_free three )

    // ── add/sub/mul with differing scales ──
    : Decimal x ( mk `12.5` )
    : Decimal y ( mk `0.025` )
    : Decimal s1 ( dec_add x y ) ( nurl_print `12.5+0.025=` ) ( pd s1 ) ( nurl_print `\n` )
    : Decimal s2 ( dec_sub x y ) ( nurl_print `12.5-0.025=` ) ( pd s2 ) ( nurl_print `\n` )
    : Decimal s3 ( dec_mul x y ) ( nurl_print `12.5*0.025=` ) ( pd s3 ) ( nurl_print `\n` )
    ( dec_free x ) ( dec_free y ) ( dec_free s1 ) ( dec_free s2 ) ( dec_free s3 )

    // ── banker's rounding (round half to even) to 2 places ──
    // 2.345 → 2.34 (4 even, half stays), 2.355 → 2.36 (5→6 even),
    // 2.346 → 2.35 (>half up), -2.345 → -2.34 (toward even)
    ( nurl_print `round 2.345→` ) : Decimal r1 ( mk `2.345` ) : Decimal rr1 ( dec_round r1 2 ) ( pd rr1 ) ( nurl_print `\n` )
    ( nurl_print `round 2.355→` ) : Decimal r2 ( mk `2.355` ) : Decimal rr2 ( dec_round r2 2 ) ( pd rr2 ) ( nurl_print `\n` )
    ( nurl_print `round 2.346→` ) : Decimal r3 ( mk `2.346` ) : Decimal rr3 ( dec_round r3 2 ) ( pd rr3 ) ( nurl_print `\n` )
    ( nurl_print `round -2.345→` ) : Decimal r4 ( mk `-2.345` ) : Decimal rr4 ( dec_round r4 2 ) ( pd rr4 ) ( nurl_print `\n` )
    ( nurl_print `round 0.125→` ) : Decimal r5 ( mk `0.125` ) : Decimal rr5 ( dec_round r5 2 ) ( pd rr5 ) ( nurl_print `\n` )  // →0.12 (even)
    ( dec_free r1 ) ( dec_free r2 ) ( dec_free r3 ) ( dec_free r4 ) ( dec_free r5 )
    ( dec_free rr1 ) ( dec_free rr2 ) ( dec_free rr3 ) ( dec_free rr4 ) ( dec_free rr5 )

    // ── division (explicit scale, banker's) ──
    ( nurl_print `1/3 @4=` ) : Decimal d1 ( mk `1` ) : Decimal d2 ( mk `3` )
    : !Decimal DecErr q1 ( dec_div d1 d2 4 ) ?? q1 { T q → { ( pd q ) ( dec_free q ) } F _ → ( nurl_print `ERR` ) } ( nurl_print `\n` )
    ( nurl_print `10/8 @2=` ) : Decimal d3 ( mk `10` ) : Decimal d4 ( mk `8` )
    : !Decimal DecErr q2 ( dec_div d3 d4 2 ) ?? q2 { T q → { ( pd q ) ( dec_free q ) } F _ → ( nurl_print `ERR` ) } ( nurl_print `\n` )  // 1.25
    ( nurl_print `1/0=` ) : Decimal d5 ( mk `1` ) : Decimal d6 ( mk `0` )
    : !Decimal DecErr q3 ( dec_div d5 d6 2 ) ?? q3 { T q → { ( pd q ) ( dec_free q ) } F e → ( nurl_print ?? e { DecDivZero → `DivZero` } ) } ( nurl_print `\n` )
    ( nurl_print `-7/2 @1=` ) : Decimal d7 ( mk `-7` ) : Decimal d8 ( mk `2` )
    : !Decimal DecErr q4 ( dec_div d7 d8 1 ) ?? q4 { T q → { ( pd q ) ( dec_free q ) } F _ → ( nurl_print `ERR` ) } ( nurl_print `\n` )  // -3.5
    ( dec_free d1 ) ( dec_free d2 ) ( dec_free d3 ) ( dec_free d4 ) ( dec_free d5 ) ( dec_free d6 ) ( dec_free d7 ) ( dec_free d8 )

    // ── normalize (strip trailing fractional zeros) ──
    ( nurl_print `normalize 1.2500→` ) : Decimal nz ( mk `1.2500` ) : Decimal nzn ( dec_normalize nz ) ( pd nzn ) ( nurl_print `\n` )
    ( dec_free nz ) ( dec_free nzn )

    // ── compare across scales ──
    : Decimal c1 ( mk `1.5` ) : Decimal c2 ( mk `1.50` )
    ( nurl_print `cmp 1.5 1.50=` ) ( nurl_print ( nurl_str_int ( dec_cmp c1 c2 ) ) )
    : Decimal c3 ( mk `1.5` ) : Decimal c4 ( mk `1.49` )
    ( nurl_print ` cmp 1.5 1.49=` ) ( nurl_print ( nurl_str_int ( dec_cmp c3 c4 ) ) ) ( nurl_print `\n` )
    ( dec_free c1 ) ( dec_free c2 ) ( dec_free c3 ) ( dec_free c4 )

    // ── a money sum: 0.10 × 3 ──
    : Decimal price ( mk `0.10` )
    : ~ Decimal acc ( dec_zero )
    : ~ i k 0
    ~ < k 3 { : Decimal nx ( dec_add acc price ) ( dec_free acc ) = acc nx = k + k 1 }
    ( nurl_print `0.10*3 (repeated add)=` ) ( pd acc ) ( nurl_print `\n` )
    ( dec_free price ) ( dec_free acc )
    ^ 0
}
