// bigint_div.nu — acceptance test for bigint_div / bigint_rem
// (stdlib/std/bigint.nu, Knuth Algorithm D). Pure computation, runs
// ungated. Covers truncated-division sign semantics across all four
// sign combinations, the a < b and exact-division edges, the
// single-limb fast path, multi-limb Algorithm D, both classic add-back
// trigger vectors (Hacker's Delight divmnu test data), a deterministic
// invariant sweep (x == q*y + r, |r| < |y|, remainder sign follows the
// dividend) over growing multi-limb operands, and the division-by-zero
// panic (caught via recover). main returns the failure count.

$ `stdlib/std/bigint.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`

// Check quotient AND remainder of x / y against expected decimal strings.
@ ck_divmod s label BigInt x BigInt y s wantq s wantr ( Vec i ) fails → v {
    : BigInt q ( bigint_div x y )
    : BigInt r ( bigint_rem x y )
    : String qs ( bigint_to_string q )
    : String rs ( bigint_to_string r )
    ? & != 0 ( nurl_str_eq ( string_data qs ) wantq ) != 0 ( nurl_str_eq ( string_data rs ) wantr ) {
        ( nurl_print `  ok   ` ) ( nurl_print label )
        ( nurl_print ` → q=` ) ( nurl_print wantq )
        ( nurl_print ` r=` ) ( nurl_print wantr ) ( nurl_print `\n` )
    } {
        ( nurl_print `  FAIL ` ) ( nurl_print label )
        ( nurl_print ` got q=` ) ( nurl_print ( string_data qs ) )
        ( nurl_print ` r=` ) ( nurl_print ( string_data rs ) )
        ( nurl_print ` want q=` ) ( nurl_print wantq )
        ( nurl_print ` r=` ) ( nurl_print wantr ) ( nurl_print `\n` )
        ( vec_push [i] fails 1 )
    }
    ( string_free qs ) ( string_free rs )
    ( bigint_free q ) ( bigint_free r )
}

// Parse a decimal literal, asserting it succeeds; on failure record it
// and return zero so the caller can keep going.
@ parse_ok s lit ( Vec i ) fails → BigInt {
    : !BigInt ParseErr r ( bigint_from_string lit )
    ?? r {
        T b → { ^ b }
        F _ → {
            ( nurl_print `  FAIL parse ` ) ( nurl_print lit ) ( nurl_print `\n` )
            ( vec_push [i] fails 1 )
            ^ ( bigint_zero )
        }
    }
}

@ big_abs BigInt v → BigInt {
    : BigInt z ( bigint_zero )
    : i c ( bigint_cmp v z )
    ( bigint_free z )
    ? < c 0 { ^ ( bigint_neg v ) } {}
    ^ ( bigint_clone v )
}

// One invariant probe: q*y + r == x, |r| < |y|, sign(r) follows sign(x).
// Returns 1 on any violation (and prints it), else 0.
@ probe BigInt x BigInt y → i {
    : ~ i bad 0
    : BigInt q ( bigint_div x y )
    : BigInt r ( bigint_rem x y )
    : BigInt qy ( bigint_mul q y )
    : BigInt rec ( bigint_add qy r )
    ? != ( bigint_cmp rec x ) 0 {
        ( nurl_print `  FAIL invariant q*y+r != x\n` )
        = bad 1
    } {}
    : BigInt ra ( big_abs r )
    : BigInt ya ( big_abs y )
    ? >= ( bigint_cmp ra ya ) 0 {
        ( nurl_print `  FAIL invariant |r| >= |y|\n` )
        = bad 1
    } {}
    : BigInt z ( bigint_zero )
    : i xs ( bigint_cmp x z )
    : i rs ( bigint_cmp r z )
    ? & >= xs 0 < rs 0 {
        ( nurl_print `  FAIL invariant sign: x >= 0 but r < 0\n` )
        = bad 1
    } {}
    ? & < xs 0 > rs 0 {
        ( nurl_print `  FAIL invariant sign: x < 0 but r > 0\n` )
        = bad 1
    } {}
    ( bigint_free z ) ( bigint_free ya ) ( bigint_free ra )
    ( bigint_free rec ) ( bigint_free qy )
    ( bigint_free r ) ( bigint_free q )
    ^ bad
}

@ run → i {
    : ( Vec i ) fails ( vec_new [i] )

    // ── truncated semantics: all four sign combinations ──
    : BigInt p7 ( bigint_from_i 7 )
    : BigInt n7 ( bigint_from_i -7 )
    : BigInt p2 ( bigint_from_i 2 )
    : BigInt n2 ( bigint_from_i -2 )
    ( ck_divmod `7/2` p7 p2 `3` `1` fails )
    ( ck_divmod `-7/2` n7 p2 `-3` `-1` fails )
    ( ck_divmod `7/-2` p7 n2 `-3` `1` fails )
    ( ck_divmod `-7/-2` n7 n2 `3` `-1` fails )
    ( bigint_free p7 ) ( bigint_free n7 )
    ( bigint_free p2 ) ( bigint_free n2 )

    // ── edges: zero dividend, a < b, exact division, x == y ──
    : BigInt z0 ( bigint_from_i 0 )
    : BigInt p5 ( bigint_from_i 5 )
    : BigInt n3 ( bigint_from_i -3 )
    ( ck_divmod `0/5` z0 p5 `0` `0` fails )
    ( ck_divmod `-3/5` n3 p5 `0` `-3` fails )
    ( ck_divmod `5/5` p5 p5 `1` `0` fails )
    : BigInt n10 ( bigint_from_i -10 )
    ( ck_divmod `-10/5` n10 p5 `-2` `0` fails )
    ( bigint_free z0 ) ( bigint_free p5 )
    ( bigint_free n3 ) ( bigint_free n10 )

    // ── single-limb fast path: 10^30 / 7 ──
    : BigInt e30 ( parse_ok `1000000000000000000000000000000` fails )
    : BigInt s7 ( bigint_from_i 7 )
    ( ck_divmod `10^30/7` e30 s7 `142857142857142857142857142857` `1` fails )
    ( bigint_free s7 )

    // ── multi-limb: (10^30 + 12345) / 10^15 ──
    : BigInt e30b ( parse_ok `1000000000000000000000000012345` fails )
    : BigInt e15 ( parse_ok `1000000000000000` fails )
    ( ck_divmod `(10^30+12345)/10^15` e30b e15 `1000000000000000` `12345` fails )
    ( bigint_free e30b ) ( bigint_free e15 ) ( bigint_free e30 )

    // ── exact multi-limb: 25! / 23! ──
    : ~ BigInt f25 ( bigint_from_i 1 )
    : ~ BigInt f23 ( bigint_from_i 1 )
    : ~ i k 2
    ~ <= k 25 {
        : BigInt kk ( bigint_from_i k )
        : BigInt nx ( bigint_mul f25 kk )
        ( bigint_free f25 )
        = f25 nx
        ? <= k 23 {
            : BigInt ny ( bigint_mul f23 kk )
            ( bigint_free f23 )
            = f23 ny
        } {}
        ( bigint_free kk )
        = k + k 1
    }
    ( ck_divmod `25!/23!` f25 f23 `600` `0` fails )
    ( bigint_free f25 ) ( bigint_free f23 )

    // ── Algorithm D add-back triggers (Hacker's Delight divmnu data) ──
    // limbs u=[0,0,0x8000,0x7fff] v=[1,0,0x8000] → q=0xfffe
    : BigInt ab1u ( parse_ok `9223231299366420480` fails )
    : BigInt ab1v ( parse_ok `140737488355329` fails )
    ( ck_divmod `add-back 1` ab1u ab1v `65534` `140737488289794` fails )
    ( bigint_free ab1u ) ( bigint_free ab1v )
    // limbs u=[0,0xfffe,0x8000] v=[0xffff,0x8000] → q=0xffff
    : BigInt ab2u ( parse_ok `140741783191552` fails )
    : BigInt ab2v ( parse_ok `2147549183` fails )
    ( ck_divmod `add-back 2` ab2u ab2v `65535` `2147483647` fails )
    ( bigint_free ab2u ) ( bigint_free ab2v )

    // ── wide multi-limb quotient + remainder ──
    : BigInt wa ( parse_ok `123456789012345678901234567890123456789` fails )
    : BigInt wb ( parse_ok `987654321098765432109` fails )
    ( ck_divmod `39-digit/21-digit` wa wb `124999998860937500` `14172067901781269289` fails )
    ( bigint_free wa ) ( bigint_free wb )

    // ── deterministic invariant sweep over growing operands ──
    // x grows ~5 digits per round, y ~4.8 — multi-limb divisors and
    // multi-limb quotients throughout; signs rotate through all four
    // combinations.
    : BigInt gx ( bigint_from_i 99991 )
    : BigInt gy ( bigint_from_i 65521 )
    : BigInt three ( bigint_from_i 3 )
    : ~ BigInt x ( bigint_from_i 1234567 )
    : ~ BigInt y ( bigint_from_i 37 )
    : ~ i bad 0
    : ~ i it 0
    ~ < it 60 {
        : BigInt itb ( bigint_from_i it )
        : BigInt xm ( bigint_mul x gx )
        : BigInt xn ( bigint_add xm itb )
        ( bigint_free x ) ( bigint_free xm )
        = x xn
        : BigInt ym ( bigint_mul y gy )
        : BigInt yn ( bigint_add ym three )
        ( bigint_free y ) ( bigint_free ym )
        = y yn
        ( bigint_free itb )

        : ~ BigInt xs ( bigint_clone x )
        ? == % it 3 0 {
            ( bigint_free xs )
            = xs ( bigint_neg x )
        } {}
        : ~ BigInt ys ( bigint_clone y )
        ? == % it 4 0 {
            ( bigint_free ys )
            = ys ( bigint_neg y )
        } {}
        = bad + bad ( probe xs ys )
        // also probe the inverted ratio (dividend smaller than divisor)
        = bad + bad ( probe ys xs )
        ( bigint_free xs ) ( bigint_free ys )
        = it + it 1
    }
    ( bigint_free x ) ( bigint_free y )
    ( bigint_free gx ) ( bigint_free gy ) ( bigint_free three )
    ? == bad 0 { ( nurl_print `  ok   invariant sweep 60 rounds x 2 probes\n` ) }
              { ( vec_push [i] fails 1 ) }

    // ── division by zero panics (and is recoverable) ──
    : BigInt dz ( bigint_from_i 42 )
    : BigInt zz ( bigint_zero )
    : !v PanicInfo pr ( recover \ → v {
        : BigInt q ( bigint_div dz zz )
        ( bigint_free q )
    } )
    ?? pr {
        T _ → {
            ( nurl_print `  FAIL div by zero did not panic\n` )
            ( vec_push [i] fails 1 )
        }
        F p → {
            ( nurl_print `  ok   div by zero → panic: ` )
            ( nurl_print ( string_data . p msg ) )
            ( nurl_print `\n` )
            ( panic_info_free p )
        }
    }
    ( bigint_free dz ) ( bigint_free zz )

    : i n ( vec_len [i] fails )
    ( vec_free [i] fails )
    ^ n
}

@ main → i {
    : i f ( run )
    ? == f 0 { ( nurl_print `bigint_div: all checks passed\n` ) }
            { ( nurl_print `bigint_div: FAILURES\n` ) }
    ^ f
}
