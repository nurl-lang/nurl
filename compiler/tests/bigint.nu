// bigint.nu — acceptance test for stdlib/std/bigint.nu. Pure computation,
// no socket, runs ungated. Covers from_i / to_string round-trips across
// the i64 range (incl. min), add/sub/mul with mixed signs, comparison,
// base-10 parse beyond i64, and a 25! magnitude check against a known
// value. main returns the failure count.

$ `stdlib/std/bigint.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`

@ ck_str s label BigInt x s expected ( Vec i ) fails → v {
    : String got ( bigint_to_string x )
    ? != 0 ( nurl_str_eq ( string_data got ) expected ) {
        ( nurl_print `  ok   ` ) ( nurl_print label )
        ( nurl_print ` = ` ) ( nurl_print expected ) ( nurl_print `\n` )
    } {
        ( nurl_print `  FAIL ` ) ( nurl_print label )
        ( nurl_print ` got ` ) ( nurl_print ( string_data got ) )
        ( nurl_print ` want ` ) ( nurl_print expected ) ( nurl_print `\n` )
        ( vec_push [i] fails 1 )
    }
    ( string_free got )
}

@ ck_int s label i got i want ( Vec i ) fails → v {
    ? == got want {
        ( nurl_print `  ok   ` ) ( nurl_print label )
        ( nurl_print ` = ` ) ( nurl_print ( nurl_str_int got ) ) ( nurl_print `\n` )
    } {
        ( nurl_print `  FAIL ` ) ( nurl_print label )
        ( nurl_print ` got ` ) ( nurl_print ( nurl_str_int got ) )
        ( nurl_print ` want ` ) ( nurl_print ( nurl_str_int want ) ) ( nurl_print `\n` )
        ( vec_push [i] fails 1 )
    }
}

// Parse a decimal literal, asserting it succeeds; on failure record it and
// return zero so the caller can keep going.
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

@ run → i {
    : ( Vec i ) fails ( vec_new [i] )

    // ── from_i / to_string across the i64 range ──
    : BigInt z ( bigint_from_i 0 )
    ( ck_str `0` z `0` fails )
    ( bigint_free z )

    : BigInt one ( bigint_from_i 1 )
    ( ck_str `1` one `1` fails )
    ( bigint_free one )

    : BigInt negone ( bigint_from_i -1 )
    ( ck_str `-1` negone `-1` fails )
    ( bigint_free negone )

    : BigInt big ( bigint_from_i 123456789 )
    ( ck_str `123456789` big `123456789` fails )
    ( bigint_free big )

    : BigInt nbig ( bigint_from_i -987654321 )
    ( ck_str `-987654321` nbig `-987654321` fails )
    ( bigint_free nbig )

    : BigInt imax ( bigint_from_i 9223372036854775807 )
    ( ck_str `i64max` imax `9223372036854775807` fails )
    ( bigint_free imax )

    : BigInt imin ( bigint_from_i -9223372036854775808 )
    ( ck_str `i64min` imin `-9223372036854775808` fails )
    ( bigint_free imin )

    // ── add ──
    : BigInt a1 ( bigint_from_i 999999999 )
    : BigInt b1 ( bigint_from_i 1 )
    : BigInt s1 ( bigint_add a1 b1 )
    ( ck_str `999999999+1` s1 `1000000000` fails )
    ( bigint_free a1 ) ( bigint_free b1 ) ( bigint_free s1 )

    // mixed-sign add that cancels toward negative
    : BigInt a2 ( bigint_from_i 3 )
    : BigInt b2 ( bigint_from_i -5 )
    : BigInt s2 ( bigint_add a2 b2 )
    ( ck_str `3+(-5)` s2 `-2` fails )
    ( bigint_free a2 ) ( bigint_free b2 ) ( bigint_free s2 )

    // mixed-sign add that cancels to zero
    : BigInt a3 ( bigint_from_i -42 )
    : BigInt b3 ( bigint_from_i 42 )
    : BigInt s3 ( bigint_add a3 b3 )
    ( ck_str `-42+42` s3 `0` fails )
    ( bigint_free a3 ) ( bigint_free b3 ) ( bigint_free s3 )

    // ── sub ──
    : BigInt d1 ( parse_ok `100000000000000000000` fails )
    : BigInt d2 ( bigint_from_i 1 )
    : BigInt ds ( bigint_sub d1 d2 )
    ( ck_str `1e20 - 1` ds `99999999999999999999` fails )
    ( bigint_free d1 ) ( bigint_free d2 ) ( bigint_free ds )

    // ── mul ──
    : BigInt m1 ( bigint_from_i 12345 )
    : BigInt m2 ( bigint_from_i 67890 )
    : BigInt mp ( bigint_mul m1 m2 )
    ( ck_str `12345*67890` mp `838102050` fails )
    ( bigint_free m1 ) ( bigint_free m2 ) ( bigint_free mp )

    // negative * negative = positive
    : BigInt n1 ( bigint_from_i -7 )
    : BigInt n2 ( bigint_from_i -8 )
    : BigInt np ( bigint_mul n1 n2 )
    ( ck_str `-7*-8` np `56` fails )
    ( bigint_free n1 ) ( bigint_free n2 ) ( bigint_free np )

    // negative * positive = negative
    : BigInt n3 ( bigint_from_i -7 )
    : BigInt n4 ( bigint_from_i 8 )
    : BigInt np2 ( bigint_mul n3 n4 )
    ( ck_str `-7*8` np2 `-56` fails )
    ( bigint_free n3 ) ( bigint_free n4 ) ( bigint_free np2 )

    // ── 25! via repeated multiply (well beyond i64) ──
    : ~ BigInt acc ( bigint_from_i 1 )
    : ~ i k 2
    ~ <= k 25 {
        : BigInt kk ( bigint_from_i k )
        : BigInt next ( bigint_mul acc kk )
        ( bigint_free acc )
        ( bigint_free kk )
        = acc next
        = k + k 1
    }
    ( ck_str `25!` acc `15511210043330985984000000` fails )
    ( bigint_free acc )

    // ── from_string round-trip beyond i64 ──
    : BigInt huge ( parse_ok `123456789012345678901234567890` fails )
    ( ck_str `parse 30-digit` huge `123456789012345678901234567890` fails )
    ( bigint_free huge )

    : BigInt nhuge ( parse_ok `-123456789012345678901234567890` fails )
    ( ck_str `parse -30-digit` nhuge `-123456789012345678901234567890` fails )
    ( bigint_free nhuge )

    // ── comparison ──
    : BigInt c1 ( parse_ok `100000000000000000000` fails )
    : BigInt c2 ( parse_ok `99999999999999999999` fails )
    ( ck_int `cmp 1e20 99..9` ( bigint_cmp c1 c2 ) 1 fails )
    ( ck_int `cmp 99..9 1e20` ( bigint_cmp c2 c1 ) -1 fails )
    ( ck_int `cmp eq` ( bigint_cmp c1 c1 ) 0 fails )
    ( bigint_free c1 ) ( bigint_free c2 )

    : BigInt neg5 ( bigint_from_i -5 )
    : BigInt pos3 ( bigint_from_i 3 )
    ( ck_int `cmp -5 vs 3` ( bigint_cmp neg5 pos3 ) -1 fails )
    : BigInt neg9 ( bigint_from_i -9 )
    ( ck_int `cmp -5 vs -9` ( bigint_cmp neg5 neg9 ) 1 fails )
    ( bigint_free neg5 ) ( bigint_free pos3 ) ( bigint_free neg9 )

    // ── parse errors ──
    : !BigInt ParseErr e1 ( bigint_from_string `` )
    ?? e1 {
        T b → { ( nurl_print `  FAIL empty parsed\n` ) ( bigint_free b ) ( vec_push [i] fails 1 ) }
        F _ → { ( nurl_print `  ok   empty → err\n` ) }
    }
    : !BigInt ParseErr e2 ( bigint_from_string `12a34` )
    ?? e2 {
        T b → { ( nurl_print `  FAIL 12a34 parsed\n` ) ( bigint_free b ) ( vec_push [i] fails 1 ) }
        F _ → { ( nurl_print `  ok   12a34 → err\n` ) }
    }
    : !BigInt ParseErr e3 ( bigint_from_string `-` )
    ?? e3 {
        T b → { ( nurl_print `  FAIL bare-sign parsed\n` ) ( bigint_free b ) ( vec_push [i] fails 1 ) }
        F _ → { ( nurl_print `  ok   "-" → err\n` ) }
    }

    : i n ( vec_len [i] fails )
    ( vec_free [i] fails )
    ^ n
}

@ main → i {
    : i f ( run )
    ? == f 0 { ( nurl_print `bigint: all checks passed\n` ) }
    { ( nurl_print `bigint: FAILURES\n` ) }
    ^ f
}
