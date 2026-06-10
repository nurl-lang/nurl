// stdlib/std/bigint.nu — arbitrary-precision signed integers.
//
// Magnitude is a little-endian vector of base-2^16 limbs (each in
// [0, 65535]), kept NORMALIZED (no high-order zero limb; the value zero
// is the empty limb vector). The sign lives in a separate `neg` flag,
// which is only ever T for a non-zero magnitude — there is no negative
// zero. Base 2^16 keeps every intermediate (a limb product plus carry)
// well inside i64, so the arithmetic never relies on unsigned overflow.
//
// API:
//   ( bigint_zero )                       → BigInt
//   ( bigint_from_i  i n )                → BigInt   (handles i64 min)
//   ( bigint_from_string s str )          → ! BigInt ParseErr
//                                            - empty / sign-only → Empty
//                                            - non-digit byte    → BadFormat
//   ( bigint_clone   BigInt x )           → BigInt
//   ( bigint_free    BigInt x )           → v
//   ( bigint_is_zero BigInt x )           → b
//   ( bigint_neg     BigInt x )           → BigInt
//   ( bigint_cmp     BigInt x BigInt y )  → i   (-1 / 0 / +1, signed)
//   ( bigint_add     BigInt x BigInt y )  → BigInt
//   ( bigint_sub     BigInt x BigInt y )  → BigInt
//   ( bigint_mul     BigInt x BigInt y )  → BigInt
//   ( bigint_to_string BigInt x )         → String  (base 10, signed)
//
// Memory: every BigInt OWNS its limb vector. Operations BORROW their
// arguments (never freed) and return a freshly-allocated BigInt; the
// caller frees each BigInt it holds with `bigint_free` (mirrors the
// `http_response_free` / `query_pairs_free` convention — plain structs
// are not auto-dropped). bigint_to_string returns an OWNED String.
//
// Not yet implemented: bignum ÷ bignum division / modulo (Knuth
// Algorithm D). Division by a single small limb exists internally
// (__mag_divmod_small_inplace) and powers base-10 formatting; the full
// quotient is tracked as a follow-up (see ROADMAP "Numeric breadth").

$ `stdlib/core/errors.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: BigInt {
    b neg
    ( Vec i ) limbs
}

@ __big_base → i { ^ 65536 }
@ __big_mask → i { ^ 65535 }
@ __big_shift → i { ^ 16 }

// Safe limb read: out-of-range index reads as 0 (lets add/sub treat a
// shorter operand as zero-extended).
@ __limb ( Vec i ) v i k → i {
    ^ ?? ( vec_get [i] v k ) { T x → x  F _ → 0 }
}

// Drop high-order zero limbs so the magnitude is canonical (zero = empty).
@ __norm ( Vec i ) v → v {
    : ~ i n ( vec_len [i] v )
    ~ & > n 0 == ( __limb v - n 1 ) 0 { = n - n 1 }
    : b _sl ( vec_set_len [i] v n )
}

@ __mag_clone ( Vec i ) a → ( Vec i ) {
    : i n ( vec_len [i] a )
    : ( Vec i ) out ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [i] out ( __limb a k ) )
        = k + k 1
    }
    ^ out
}

// Compare two NORMALIZED magnitudes: -1 / 0 / +1.
@ __mag_cmp ( Vec i ) a ( Vec i ) b → i {
    : i na ( vec_len [i] a )
    : i nb ( vec_len [i] b )
    ? > na nb { ^ 1 } {}
    ? < na nb { ^ -1 } {}
    : ~ i k - na 1
    : ~ i res 0
    : ~ b done F
    ~ & ! done >= k 0 {
        : i av ( __limb a k )
        : i bv ( __limb b k )
        ? > av bv { = res 1 = done T } {}
        ? & ! done < av bv { = res -1 = done T } {}
        = k - k 1
    }
    ^ res
}

// Magnitude add (a + b), schoolbook with carry.
@ __mag_add ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : i na ( vec_len [i] a )
    : i nb ( vec_len [i] b )
    : i n ? > na nb na nb
    : ( Vec i ) out ( vec_with_cap [i] + n 1 )
    : ~ i carry 0
    : ~ i k 0
    ~ < k n {
        : i s + + ( __limb a k ) ( __limb b k ) carry
        ( vec_push [i] out & s ( __big_mask ) )
        = carry >> s ( __big_shift )
        = k + k 1
    }
    ? > carry 0 { ( vec_push [i] out carry ) } {}
    ( __norm out )
    ^ out
}

// Magnitude sub (a - b), REQUIRES a >= b. Borrow propagation.
@ __mag_sub ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : i na ( vec_len [i] a )
    : ( Vec i ) out ( vec_with_cap [i] na )
    : ~ i borrow 0
    : ~ i k 0
    ~ < k na {
        : ~ i d - - ( __limb a k ) ( __limb b k ) borrow
        ? < d 0 { = d + d ( __big_base ) = borrow 1 } { = borrow 0 }
        ( vec_push [i] out d )
        = k + k 1
    }
    ( __norm out )
    ^ out
}

// Magnitude mul (a * b), schoolbook. Empty operand → zero.
@ __mag_mul ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : i na ( vec_len [i] a )
    : i nb ( vec_len [i] b )
    ? | == na 0 == nb 0 { ^ ( vec_new [i] ) } {}
    : ( Vec i ) out ( vec_with_cap [i] + na nb )
    : ~ i z 0
    ~ < z + na nb {
        ( vec_push [i] out 0 )
        = z + z 1
    }
    // No more pushes past here → the data pointer stays valid.
    : *i op ( vec_data [i] out )
    : ~ i i 0
    ~ < i na {
        : i ai ( __limb a i )
        : ~ i carry 0
        : ~ i j 0
        ~ < j nb {
            : i idx + i j
            : i prod + + # i . op idx * ai ( __limb b j ) carry
            = . op idx & prod ( __big_mask )
            = carry >> prod ( __big_shift )
            = j + j 1
        }
        : ~ i idx2 + i nb
        ~ > carry 0 {
            : i s2 + # i . op idx2 carry
            = . op idx2 & s2 ( __big_mask )
            = carry >> s2 ( __big_shift )
            = idx2 + idx2 1
        }
        = i + i 1
    }
    ( __norm out )
    ^ out
}

// Divide a magnitude by a single small divisor (1 <= d < 2^16) IN PLACE;
// `a` becomes the quotient (normalized) and the remainder is returned.
@ __mag_divmod_small_inplace ( Vec i ) a i d → i {
    : i n ( vec_len [i] a )
    ? == n 0 { ^ 0 } {}
    : *i ap ( vec_data [i] a )
    : ~ i rem 0
    : ~ i k - n 1
    ~ >= k 0 {
        : i cur + * rem ( __big_base ) # i . ap k
        = . ap k / cur d
        = rem % cur d
        = k - k 1
    }
    ( __norm a )
    ^ rem
}

// a := a * m + add IN PLACE, with small m and add (used by parsing).
@ __mag_mul_add_small_inplace ( Vec i ) a i m i add → v {
    : i n ( vec_len [i] a )
    : ~ i carry add
    ? > n 0 {
        : *i ap ( vec_data [i] a )
        : ~ i k 0
        ~ < k n {
            : i cur + * # i . ap k m carry
            = . ap k & cur ( __big_mask )
            = carry >> cur ( __big_shift )
            = k + k 1
        }
    } {}
    ~ > carry 0 {
        ( vec_push [i] a & carry ( __big_mask ) )
        = carry >> carry ( __big_shift )
    }
    ( __norm a )
}

// ── Public constructors ───────────────────────────────────────────────

@ bigint_zero → BigInt {
    ^ @ BigInt { F ( vec_new [i] ) }
}

@ bigint_from_i i n → BigInt {
    // i64 min: |n| = 2^63 = limbs [0, 0, 0, 0x8000]; -n would overflow.
    ? == n -9223372036854775808 {
        : ( Vec i ) lm ( vec_new [i] )
        ( vec_push [i] lm 0 )
        ( vec_push [i] lm 0 )
        ( vec_push [i] lm 0 )
        ( vec_push [i] lm 32768 )
        ^ @ BigInt { T lm }
    } {}
    : ~ b neg F
    : ~ i mag n
    ? < n 0 { = neg T = mag - 0 n } {}
    : ( Vec i ) lm ( vec_new [i] )
    ~ > mag 0 {
        ( vec_push [i] lm & mag ( __big_mask ) )
        = mag >> mag ( __big_shift )
    }
    ^ @ BigInt { neg lm }
}

@ bigint_clone BigInt x → BigInt {
    ^ @ BigInt { . x neg ( __mag_clone . x limbs ) }
}

@ bigint_free BigInt x → v {
    ( vec_free [i] . x limbs )
}

@ bigint_is_zero BigInt x → b {
    ^ == ( vec_len [i] . x limbs ) 0
}

@ bigint_neg BigInt x → BigInt {
    : ( Vec i ) lm ( __mag_clone . x limbs )
    : b neg & ! . x neg > ( vec_len [i] lm ) 0
    ^ @ BigInt { neg lm }
}

// ── Comparison ────────────────────────────────────────────────────────

@ bigint_cmp BigInt x BigInt y → i {
    : b xz ( bigint_is_zero x )
    : b yz ( bigint_is_zero y )
    ? & xz yz { ^ 0 } {}
    : b xn & ! xz . x neg
    : b yn & ! yz . y neg
    ? & xn ! yn { ^ -1 } {}
    ? & ! xn yn { ^ 1 } {}
    : i mc ( __mag_cmp . x limbs . y limbs )
    // Both negative → larger magnitude is the smaller value.
    ? xn { ^ - 0 mc } {}
    ^ mc
}

// ── Arithmetic ────────────────────────────────────────────────────────

@ bigint_add BigInt x BigInt y → BigInt {
    ? == . x neg . y neg {
        // Same sign: add magnitudes, keep the sign (zero stays positive).
        : ( Vec i ) m ( __mag_add . x limbs . y limbs )
        : b neg & . x neg > ( vec_len [i] m ) 0
        ^ @ BigInt { neg m }
    } {}
    // Opposite signs: subtract the smaller magnitude from the larger; the
    // result takes the sign of the larger magnitude.
    : i c ( __mag_cmp . x limbs . y limbs )
    ? == c 0 { ^ ( bigint_zero ) } {}
    ? > c 0 {
        ^ @ BigInt { . x neg ( __mag_sub . x limbs . y limbs ) }
    } {}
    ^ @ BigInt { . y neg ( __mag_sub . y limbs . x limbs ) }
}

@ bigint_sub BigInt x BigInt y → BigInt {
    : BigInt ny ( bigint_neg y )
    : BigInt r ( bigint_add x ny )
    ( bigint_free ny )
    ^ r
}

@ bigint_mul BigInt x BigInt y → BigInt {
    : ( Vec i ) m ( __mag_mul . x limbs . y limbs )
    : b neg & != . x neg . y neg > ( vec_len [i] m ) 0
    ^ @ BigInt { neg m }
}

// ── Formatting / parsing ──────────────────────────────────────────────

// Append `g` (0..9999) as exactly four decimal digits (zero-padded).
@ __push_group4 String out i g → v {
    ( string_push_char out + 48 / g 1000 )
    ( string_push_char out + 48 % / g 100 10 )
    ( string_push_char out + 48 % / g 10 10 )
    ( string_push_char out + 48 % g 10 )
}

// Append `g` (1..9999) with no leading zeros — for the leading group.
@ __push_group_lead String out i g → v {
    ? >= g 1000 { ( string_push_char out + 48 / g 1000 ) } {}
    ? >= g 100 { ( string_push_char out + 48 % / g 100 10 ) } {}
    ? >= g 10 { ( string_push_char out + 48 % / g 10 10 ) } {}
    ( string_push_char out + 48 % g 10 )
}

@ bigint_to_string BigInt x → String {
    ? ( bigint_is_zero x ) {
        : String z ( string_new )
        ( string_push_char z 48 )
        ^ z
    } {}
    // Repeatedly divide a working copy by 10000, collecting base-10000
    // groups little-endian.
    : ( Vec i ) work ( __mag_clone . x limbs )
    : ( Vec i ) groups ( vec_new [i] )
    ~ > ( vec_len [i] work ) 0 {
        : i r ( __mag_divmod_small_inplace work 10000 )
        ( vec_push [i] groups r )
    }
    ( vec_free [i] work )
    : String out ( string_new )
    ? . x neg { ( string_push_char out 45 ) } {}
    : i ng ( vec_len [i] groups )
    : ~ i gi - ng 1
    : ~ b first T
    ~ >= gi 0 {
        : i g ( __limb groups gi )
        ? first {
            ( __push_group_lead out g )
            = first F
        } {
            ( __push_group4 out g )
        }
        = gi - gi 1
    }
    ( vec_free [i] groups )
    ^ out
}

@ bigint_from_string s str → !BigInt ParseErr {
    : i n ( nurl_str_len str )
    ? == n 0 { ^ @ !BigInt ParseErr { F @ ParseErr { Empty } } } {}
    : ~ i i 0
    : ~ b neg F
    : i c0 ( nurl_str_get str 0 )
    ? == c0 45 { = neg T = i 1 } {}
    ? == c0 43 { = i 1 } {}
    ? >= i n { ^ @ !BigInt ParseErr { F @ ParseErr { Empty } } } {}
    : ( Vec i ) mag ( vec_new [i] )
    : ~ b ok T
    ~ & ok < i n {
        : i ch ( nurl_str_get str i )
        ? & >= ch 48 <= ch 57 {
            ( __mag_mul_add_small_inplace mag 10 - ch 48 )
        } { = ok F }
        = i + i 1
    }
    ? ! ok {
        ( vec_free [i] mag )
        ^ @ !BigInt ParseErr { F @ ParseErr { BadFormat } }
    } {}
    : b fneg & neg > ( vec_len [i] mag ) 0
    ^ @ !BigInt ParseErr { T @ BigInt { fneg mag } }
}
