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
//   ( bigint_div     BigInt x BigInt y )  → BigInt  (truncated quotient)
//   ( bigint_rem     BigInt x BigInt y )  → BigInt  (sign of the dividend)
//   ( bigint_to_string BigInt x )         → String  (base 10, signed)
//
// Division is TRUNCATED (the quotient rounds toward zero, the remainder
// takes the dividend's sign), matching the native `/` and `%` on `i` —
// so for any y ≠ 0:  x == (x/y)*y + x%y  and  |x%y| < |y|.
// Division by zero PANICS (`panic`, recoverable via `recover`): it is a
// program defect, not a data error, so it is not threaded through `!`.
// The magnitude core is Knuth Algorithm D (TAOCP vol. 2, 4.3.1) over the
// base-2^16 limbs; a single-limb divisor short-circuits through
// __mag_divmod_small_inplace.
//
// Memory: every BigInt OWNS its limb vector. Operations BORROW their
// arguments (never freed) and return a freshly-allocated BigInt; the
// caller frees each BigInt it holds with `bigint_free` (mirrors the
// `http_response_free` / `query_pairs_free` convention — plain structs
// are not auto-dropped). bigint_to_string returns an OWNED String.

$ `stdlib/core/errors.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

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
    ^ ?? ( vec_get [i] v k ) { T x → x F _ → 0 }
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

// Magnitude divmod (Knuth Algorithm D). Both inputs NORMALIZED, `bdiv`
// non-empty. Returns a fresh normalized quotient magnitude; the
// normalized remainder limbs are appended to `rem` (caller passes it in
// EMPTY). Borrows `a` and `bdiv`.
@ __mag_divmod ( Vec i ) a ( Vec i ) bdiv ( Vec i ) rem → ( Vec i ) {
    // a < b: quotient zero, remainder a.
    ? < ( __mag_cmp a bdiv ) 0 {
        : i nca ( vec_len [i] a )
        : ~ i t 0
        ~ < t nca {
            ( vec_push [i] rem ( __limb a t ) )
            = t + t 1
        }
        ^ ( vec_new [i] )
    } {}
    : i nb ( vec_len [i] bdiv )
    // Single-limb divisor: the small in-place routine is exact.
    ? == nb 1 {
        : ( Vec i ) q ( __mag_clone a )
        : i r ( __mag_divmod_small_inplace q ( __limb bdiv 0 ) )
        ? > r 0 { ( vec_push [i] rem r ) } {}
        ^ q
    } {}
    : i na ( vec_len [i] a )
    // D1 normalize: scale both by d = 2^k so the top divisor limb is
    // >= base/2 (makes every trial digit off by at most 1). Reuses the
    // small-multiply helper, so no shift primitives are needed.
    : ~ i d 1
    : ~ i top ( __limb bdiv - nb 1 )
    ~ < top 32768 {
        = top * top 2
        = d * d 2
    }
    : ( Vec i ) un ( __mag_clone a )
    ( __mag_mul_add_small_inplace un d 0 )
    ~ < ( vec_len [i] un ) + na 1 { ( vec_push [i] un 0 ) }
    : ( Vec i ) vn ( __mag_clone bdiv )
    ( __mag_mul_add_small_inplace vn d 0 )
    : i m - na nb
    : ( Vec i ) q ( vec_with_cap [i] + m 1 )
    : ~ i z 0
    ~ <= z m {
        ( vec_push [i] q 0 )
        = z + z 1
    }
    // No more pushes into un/vn/q past here → data pointers stay valid.
    : *i up ( vec_data [i] un )
    : *i vp ( vec_data [i] vn )
    : *i qp ( vec_data [i] q )
    : i vh # i . vp - nb 1
    : i vl # i . vp - nb 2
    : ~ i j m
    ~ >= j 0 {
        // D3 trial digit from the top two dividend limbs; the two-limb
        // value is < base^2 so it stays well inside i64.
        : i u2 + * # i . up + j nb ( __big_base ) # i . up - + j nb 1
        : ~ i qhat / u2 vh
        : ~ i rhat % u2 vh
        : i ulo # i . up + j - nb 2
        : ~ b adj T
        ~ adj {
            ? | >= qhat ( __big_base ) > * qhat vl + * rhat ( __big_base ) ulo {
                = qhat - qhat 1
                = rhat + rhat vh
                ? >= rhat ( __big_base ) { = adj F } {}
            } { = adj F }
        }
        // D4 multiply-and-subtract: u[j .. j+nb] -= qhat * v, schoolbook
        // with a per-limb {0,1} borrow (no negative shifts needed).
        : ( Vec i ) qv ( __mag_clone vn )
        ( __mag_mul_add_small_inplace qv qhat 0 )
        : ~ i borrow 0
        : ~ i t2 0
        ~ <= t2 nb {
            : ~ i dd - - # i . up + t2 j ( __limb qv t2 ) borrow
            ? < dd 0 {
                = dd + dd ( __big_base )
                = borrow 1
            } { = borrow 0 }
            = . up + t2 j dd
            = t2 + t2 1
        }
        ( vec_free [i] qv )
        // D6 add back (rare: probability ~2/base per digit): the trial
        // digit was one too large — undo by adding v once. The top-limb
        // carry wraps mod base, cancelling the outstanding borrow.
        ? > borrow 0 {
            = qhat - qhat 1
            : ~ i c2 0
            : ~ i t3 0
            ~ < t3 nb {
                : i s2 + + # i . up + t3 j # i . vp t3 c2
                = . up + t3 j & s2 ( __big_mask )
                = c2 >> s2 ( __big_shift )
                = t3 + t3 1
            }
            = . up + j nb & + # i . up + j nb c2 ( __big_mask )
        } {}
        = . qp j qhat
        = j - j 1
    }
    // D8 un-normalize: the remainder is u[0 .. nb) / d.
    : ~ i t4 0
    ~ < t4 nb {
        ( vec_push [i] rem # i . up t4 )
        = t4 + t4 1
    }
    ( __norm rem )
    ? > d 1 { : i _r ( __mag_divmod_small_inplace rem d ) } {}
    ( vec_free [i] un )
    ( vec_free [i] vn )
    ( __norm q )
    ^ q
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

// Truncated quotient (rounds toward zero), matching the native `/`.
// Panics on a zero divisor.
@ bigint_div BigInt x BigInt y → BigInt {
    ? ( bigint_is_zero y ) { ( panic `bigint_div: division by zero` ) } {}
    : ( Vec i ) rm ( vec_new [i] )
    : ( Vec i ) qm ( __mag_divmod . x limbs . y limbs rm )
    ( vec_free [i] rm )
    : b neg & != . x neg . y neg > ( vec_len [i] qm ) 0
    ^ @ BigInt { neg qm }
}

// Remainder of truncated division (takes the dividend's sign), matching
// the native `%`: x == (x/y)*y + x%y. Panics on a zero divisor.
@ bigint_rem BigInt x BigInt y → BigInt {
    ? ( bigint_is_zero y ) { ( panic `bigint_rem: division by zero` ) } {}
    : ( Vec i ) rm ( vec_new [i] )
    : ( Vec i ) qm ( __mag_divmod . x limbs . y limbs rm )
    ( vec_free [i] qm )
    : b neg & . x neg > ( vec_len [i] rm ) 0
    ^ @ BigInt { neg rm }
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

// ── byte I/O + modular exponentiation (RSA / DH support) ──────────
// These let BigInt carry cryptographic integers (moduli, signatures)
// to and from their big-endian wire form and do s^e mod n.

// Big-endian bytes → non-negative BigInt.
@ bigint_from_bytes_be ( Vec u ) b → BigInt {
    : i n ( vec_len [u] b )
    : ( Vec i ) limbs ( vec_new [i] )
    : ~ i i - n 1
    ~ >= i 0 {
        : i lo ?? ( vec_get [u] b i ) { T x → # i x F _ → 0 }
        : ~ i hi 0
        ? > i 0 { = hi ?? ( vec_get [u] b - i 1 ) { T x → # i x F _ → 0 } } {}
        ( vec_push [i] limbs | lo << hi 8 )
        = i - i 2
    }
    ( __norm limbs )
    ^ @ BigInt { F limbs }
}

// Non-negative BigInt → big-endian bytes, left-padded with zeros to at
// least `minlen` (use 0 for the minimal encoding). RSA wants the result
// padded to the modulus byte-length.
@ bigint_to_bytes_be BigInt x i minlen → ( Vec u ) {
    : ( Vec i ) limbs . x limbs
    : i nl ( vec_len [i] limbs )
    : ( Vec u ) le ( vec_new [u] )
    : ~ i k 0
    ~ < k nl {
        : i v ( __limb limbs k )
        ( vec_push [u] le # u & v 255 )
        ( vec_push [u] le # u & >> v 8 255 )
        = k + k 1
    }
    : ~ i len ( vec_len [u] le )
    ~ & > len 0 == ?? ( vec_get [u] le - len 1 ) { T b → # i b F _ → 0 } 0 { = len - len 1 }
    : i outlen ? > minlen len minlen len
    : ( Vec u ) out ( vec_with_cap [u] ? > outlen 0 outlen 1 )
    : ~ i pad - outlen len
    ~ > pad 0 { ( vec_push [u] out # u 0 ) = pad - pad 1 }
    : ~ i j - len 1
    ~ >= j 0 {
        ( vec_push [u] out ?? ( vec_get [u] le j ) { T b → b F _ → # u 0 } )
        = j - j 1
    }
    ( vec_free [u] le )
    ^ out
}

// base^exp mod m, all non-negative. Square-and-multiply over exp's bits.
@ bigint_modpow BigInt base BigInt exp BigInt m → BigInt {
    : ~ BigInt result ( bigint_from_i 1 )
    : BigInt two ( bigint_from_i 2 )
    : ~ BigInt b ( bigint_rem base m )
    : ~ BigInt e ( bigint_clone exp )
    ~ ! ( bigint_is_zero e ) {
        : BigInt r ( bigint_rem e two )
        ? ! ( bigint_is_zero r ) {
            : BigInt t ( bigint_mul result b )
            : BigInt t2 ( bigint_rem t m )
            ( bigint_free result )
            ( bigint_free t )
            = result t2
        } {}
        ( bigint_free r )
        : BigInt bb ( bigint_mul b b )
        : BigInt bb2 ( bigint_rem bb m )
        ( bigint_free b )
        ( bigint_free bb )
        = b bb2
        : BigInt e2 ( bigint_div e two )
        ( bigint_free e )
        = e e2
    }
    ( bigint_free b )
    ( bigint_free e )
    ( bigint_free two )
    ^ result
}
