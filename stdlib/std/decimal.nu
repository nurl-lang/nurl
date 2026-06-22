// stdlib/std/decimal.nu — arbitrary-precision fixed-point decimal.
//
// A `Decimal` is an exact base-10 number: an arbitrary-precision integer
// coefficient (`BigInt`, from std/bigint.nu) times a power of ten given
// by an explicit non-negative `scale`:
//
//     value = coeff × 10^(-scale)        e.g.  12345 × 10^-2 = 123.45
//
// This is what money math needs — `0.1 + 0.2` is exactly `0.3`, never the
// binary-float `0.30000000000000004` — and it never overflows, since the
// coefficient grows as large as the value demands. Division (the only
// inexact operation) takes an explicit result scale and rounds
// **half-to-even** (banker's rounding), the IEEE 754 / financial default
// that avoids the upward bias of round-half-up.
//
// Ownership: a Decimal owns its BigInt coefficient — `dec_free` it (or
// the values it was built from). Every operation returns a fresh owned
// Decimal; inputs are borrowed and untouched.
//
//   ( dec_from_i n )                  → Decimal          n × 10^0
//   ( dec_from_string s )             → !Decimal ParseErr "-12.340", ".5", "42"
//   ( dec_zero )                      → Decimal
//   ( dec_clone d ) / ( dec_free d )
//   ( dec_scale d )                   → i                fractional digit count
//   ( dec_is_zero d )                 → b
//   ( dec_neg d )                     → Decimal
//   ( dec_add a b ) ( dec_sub a b ) ( dec_mul a b ) → Decimal   (exact)
//   ( dec_div a b scale )             → !Decimal DecErr  banker's-rounded
//   ( dec_cmp a b )                   → i                -1 / 0 / 1, scale-agnostic
//   ( dec_round d places )            → Decimal          half-to-even to `places`
//   ( dec_rescale d scale )           → Decimal          change scale (round if fewer)
//   ( dec_normalize d )               → Decimal          drop trailing fractional zeros
//   ( dec_to_string d )               → String

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/std/bigint.nu`

: Decimal { BigInt coeff i scale }

: | DecErr { DecDivZero }

@ dec_free Decimal d → v { ( bigint_free . d coeff ) }

@ dec_clone Decimal d → Decimal { ^ @ Decimal { ( bigint_clone . d coeff ) . d scale } }

@ dec_scale Decimal d → i { ^ . d scale }

@ dec_is_zero Decimal d → b { ^ ( bigint_is_zero . d coeff ) }

@ dec_zero → Decimal { ^ @ Decimal { ( bigint_zero ) 0 } }

@ dec_from_i i n → Decimal { ^ @ Decimal { ( bigint_from_i n ) 0 } }

@ dec_neg Decimal d → Decimal { ^ @ Decimal { ( bigint_neg . d coeff ) . d scale } }

// ── internal bigint helpers ─────────────────────────────────────────

// 10^d as a BigInt (d ≥ 0).
@ __dec_pow10 i d → BigInt {
    : ~ BigInt acc ( bigint_from_i 1 )
    : BigInt ten ( bigint_from_i 10 )
    : ~ i k 0
    ~ < k d {
        : BigInt nx ( bigint_mul acc ten )
        ( bigint_free acc )
        = acc nx
        = k + k 1
    }
    ( bigint_free ten )
    ^ acc
}

// `c × 10^delta` as a fresh BigInt (delta ≥ 0). delta == 0 still returns
// a fresh copy, so callers can always free the source.
@ __dec_scaleup BigInt c i delta → BigInt {
    : BigInt p ( __dec_pow10 delta )
    : BigInt r ( bigint_mul c p )
    ( bigint_free p )
    ^ r
}

// True iff non-negative `x` is odd.
@ __bigint_is_odd BigInt x → b {
    : BigInt two ( bigint_from_i 2 )
    : BigInt r ( bigint_rem x two )
    : b odd ! ( bigint_is_zero r )
    ( bigint_free two ) ( bigint_free r )
    ^ odd
}

// round-half-to-even( num / den ), both NON-NEGATIVE, den > 0. Returns a
// fresh non-negative BigInt.
@ __dec_round_div BigInt num BigInt den → BigInt {
    : BigInt q ( bigint_div num den )
    : BigInt r ( bigint_rem num den )
    : BigInt twor ( bigint_add r r )  // 2·remainder
    : i c ( bigint_cmp twor den )
    ( bigint_free r ) ( bigint_free twor )
    // 2r > den → round up; 2r < den → round down (keep q);
    // 2r == den (exactly half) → round to even.
    : ~ b bump F
    ? > c 0 { = bump T } {
        ? == c 0 { ? ( __bigint_is_odd q ) { = bump T } {} } {}
    }
    ? bump {
        : BigInt one ( bigint_from_i 1 )
        : BigInt res ( bigint_add q one )
        ( bigint_free one ) ( bigint_free q )
        ^ res
    } {}
    ^ q
}

// ── add / sub / mul / cmp ───────────────────────────────────────────

@ __dec_max_scale Decimal a Decimal b → i {
    ^ ? > . a scale . b scale . a scale . b scale
}

@ dec_add Decimal a Decimal b → Decimal {
    : i s ( __dec_max_scale a b )
    : BigInt ca ( __dec_scaleup . a coeff - s . a scale )
    : BigInt cb ( __dec_scaleup . b coeff - s . b scale )
    : BigInt sum ( bigint_add ca cb )
    ( bigint_free ca ) ( bigint_free cb )
    ^ @ Decimal { sum s }
}

@ dec_sub Decimal a Decimal b → Decimal {
    : i s ( __dec_max_scale a b )
    : BigInt ca ( __dec_scaleup . a coeff - s . a scale )
    : BigInt cb ( __dec_scaleup . b coeff - s . b scale )
    : BigInt diff ( bigint_sub ca cb )
    ( bigint_free ca ) ( bigint_free cb )
    ^ @ Decimal { diff s }
}

@ dec_mul Decimal a Decimal b → Decimal {
    : BigInt c ( bigint_mul . a coeff . b coeff )
    ^ @ Decimal { c + . a scale . b scale }
}

@ dec_cmp Decimal a Decimal b → i {
    : i s ( __dec_max_scale a b )
    : BigInt ca ( __dec_scaleup . a coeff - s . a scale )
    : BigInt cb ( __dec_scaleup . b coeff - s . b scale )
    : i c ( bigint_cmp ca cb )
    ( bigint_free ca ) ( bigint_free cb )
    ^ c
}

// ── rescale / round / normalize ─────────────────────────────────────

@ dec_rescale Decimal d i target → Decimal {
    ? == target . d scale { ^ ( dec_clone d ) } {}
    ? > target . d scale {
        : BigInt c ( __dec_scaleup . d coeff - target . d scale )
        ^ @ Decimal { c target }
    } {}
    // fewer digits: drop (scale - target) with banker's rounding.
    : i drop - . d scale target
    : BigInt div ( __dec_pow10 drop )
    : BigInt c0 . d coeff
    : b neg & ! ( bigint_is_zero c0 ) . c0 neg
    : BigInt mag ? neg ( bigint_neg c0 ) ( bigint_clone c0 )
    : BigInt rq ( __dec_round_div mag div )
    : BigInt coeff ? neg ( bigint_neg rq ) ( bigint_clone rq )
    ( bigint_free div ) ( bigint_free mag ) ( bigint_free rq )
    ^ @ Decimal { coeff target }
}

@ dec_round Decimal d i places → Decimal { ^ ( dec_rescale d places ) }

@ dec_normalize Decimal d → Decimal {
    : ~ BigInt c ( bigint_clone . d coeff )
    : ~ i s . d scale
    : BigInt ten ( bigint_from_i 10 )
    : ~ b going T
    ~ & going > s 0 {
        : BigInt r ( bigint_rem c ten )
        : b divisible ( bigint_is_zero r )
        ( bigint_free r )
        ? divisible {
            : BigInt q ( bigint_div c ten )
            ( bigint_free c )
            = c q
            = s - s 1
        } { = going F }
    }
    ( bigint_free ten )
    ^ @ Decimal { c s }
}

// ── division (banker's rounding to `scale` places) ──────────────────

@ dec_div Decimal a Decimal b i scale → !Decimal DecErr {
    ? ( bigint_is_zero . b coeff ) { ^ @ !Decimal DecErr { F DecDivZero } } {}
    // result = (a.coeff·10^(scale+b.scale)) / (b.coeff·10^a.scale)
    : BigInt num ( __dec_scaleup . a coeff + scale . b scale )
    : BigInt den ( __dec_scaleup . b coeff . a scale )
    : b negN & ! ( bigint_is_zero num ) . num neg
    : b negD & ! ( bigint_is_zero den ) . den neg
    : BigInt aN ? negN ( bigint_neg num ) ( bigint_clone num )
    : BigInt aD ? negD ( bigint_neg den ) ( bigint_clone den )
    : BigInt q ( __dec_round_div aN aD )
    : b rneg != negN negD
    : BigInt coeff ? rneg ( bigint_neg q ) ( bigint_clone q )
    ( bigint_free num ) ( bigint_free den )
    ( bigint_free aN ) ( bigint_free aD ) ( bigint_free q )
    ^ @ !Decimal DecErr { T @ Decimal { coeff scale } }
}

// ── string I/O ──────────────────────────────────────────────────────

@ dec_to_string Decimal d → String {
    : String signed ( bigint_to_string . d coeff )
    : s ss ( string_data signed )
    : b neg & > ( nurl_str_len ss ) 0 == ( nurl_str_get ss 0 ) 45
    : i dstart ? neg 1 0
    : i dlen - ( nurl_str_len ss ) dstart  // count of magnitude digits
    : i scale . d scale
    : String out ( string_with_cap + + dlen scale 4 )
    ? neg { ( string_push_char out 45 ) } {}
    ? == scale 0 {
        : ~ i k dstart
        ~ < k ( nurl_str_len ss ) { ( string_push_char out ( nurl_str_get ss k ) ) = k + k 1 }
        ( string_free signed )
        ^ out
    } {}
    ? > dlen scale {
        // integer part has (dlen - scale) digits
        : i split + dstart - dlen scale
        : ~ i k dstart
        ~ < k split { ( string_push_char out ( nurl_str_get ss k ) ) = k + k 1 }
        ( string_push_char out 46 )  // '.'
        = k split
        ~ < k ( nurl_str_len ss ) { ( string_push_char out ( nurl_str_get ss k ) ) = k + k 1 }
    } {
        // |value| < 1 : "0." then (scale - dlen) leading zeros then digits
        ( string_push_char out 48 )  // '0'
        ( string_push_char out 46 )  // '.'
        : ~ i z 0
        ~ < z - scale dlen { ( string_push_char out 48 ) = z + z 1 }
        : ~ i k dstart
        ~ < k ( nurl_str_len ss ) { ( string_push_char out ( nurl_str_get ss k ) ) = k + k 1 }
    }
    ( string_free signed )
    ^ out
}

@ dec_from_string s str → !Decimal ParseErr {
    : i n ( nurl_str_len str )
    ? == n 0 { ^ @ !Decimal ParseErr { F @ ParseErr { Empty } } } {}
    : ~ i pos 0
    : String digits ( string_with_cap + n 1 )  // sign + all coefficient digits
    : i c0 ( nurl_str_get str 0 )
    ? | == c0 45 == c0 43 {
        ? == c0 45 { ( string_push_char digits 45 ) } {}
        = pos 1
    } {}
    : ~ i int_digits 0
    : ~ i frac_digits 0
    : ~ b seen_dot F
    : ~ b bad F
    ~ & < pos n ! bad {
        : i c ( nurl_str_get str pos )
        ? & >= c 48 <= c 57 {
            ( string_push_char digits c )
            ? seen_dot { = frac_digits + frac_digits 1 } { = int_digits + int_digits 1 }
        } {
            ? & == c 46 ! seen_dot { = seen_dot T } { = bad T }
        }
        = pos + pos 1
    }
    ? bad { ( string_free digits ) ^ @ !Decimal ParseErr { F @ ParseErr { BadFormat } } } {}
    ? == 0 + int_digits frac_digits { ( string_free digits ) ^ @ !Decimal ParseErr { F @ ParseErr { Empty } } } {}
    : !BigInt ParseErr cr ( bigint_from_string ( string_data digits ) )
    ( string_free digits )
    ^ ?? cr {
        T coeff → @ !Decimal ParseErr { T @ Decimal { coeff frac_digits } }
        F e → @ !Decimal ParseErr { F e }
    }
}
