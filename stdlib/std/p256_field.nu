// stdlib/std/p256_field.nu — constant-time GF(p) arithmetic for NIST P-256.
//
// A dedicated FIXED-WIDTH field: every element is exactly 16 little-endian
// 16-bit limbs (256 bits), NEVER normalized/trimmed, so no operation's
// duration depends on the value. This is the constant-time core the generic
// std/bigint.nu cannot be (it trims leading-zero limbs → operand-time-
// dependent). Multiplication is Montgomery CIOS; add/sub use a constant-time
// conditional ±p; inversion is a fixed Fermat chain (a^(p-2)). All loops are
// fixed-count and branch-free in the data.
//
// Elements live in Montgomery form (ā = a·R mod p, R = 2^256) so that
// p256ct_mul ā b̄ = (a·b)·R mod p stays in form. Convert in with
// p256ct_to_mont, out with p256ct_from_mont. Used by the secret-scalar P-256
// point multiply (ECDSA nonce / ECDH); verify keeps the public bigint path.

$ `stdlib/core/vec.nu`

// p = 2^256 − 2^224 + 2^192 + 2^96 − 1, little-endian 16-bit limbs.
@ __p256_mod → ( Vec i ) {
    // Filled by index, not pushed: p256ct_mul rebuilds this on every one
    // of the ~3000 field operations a scalar multiply performs, and a
    // push carries a capacity check the fixed sixteen limbs do not need.
    : ( Vec i ) v ( __mag16 )
    : *i q ( vec_data [i] v )
    = . q 0 65535 = . q 1 65535 = . q 2 65535 = . q 3 65535
    = . q 4 65535 = . q 5 65535 = . q 6 0 = . q 7 0
    = . q 8 0 = . q 9 0 = . q 10 0 = . q 11 0
    = . q 12 1 = . q 13 0 = . q 14 65535 = . q 15 65535
    ^ v
}

// R^2 mod p (= 2^512 mod p) — multiply by this (Montgomery) to enter the domain.
@ __p256_r2 → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 16 )
    ( vec_push [i] v 3 ) ( vec_push [i] v 0 ) ( vec_push [i] v 0 ) ( vec_push [i] v 0 )
    ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 65531 ) ( vec_push [i] v 65535 )
    ( vec_push [i] v 65534 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 )
    ( vec_push [i] v 65533 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 4 ) ( vec_push [i] v 0 )
    ^ v
}

// 1 in plain (non-Montgomery) form: [1, 0, …]. Montgomery-multiplying by this
// leaves the domain (montmul(ā, 1) = a).
@ __p256_one → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 16 )
    ( vec_push [i] v 1 )
    : ~ i k 1
    ~ < k 16 { ( vec_push [i] v 0 ) = k + k 1 }
    ^ v
}

// -p^-1 mod 2^16. For p ≡ −1 (mod 2^16) this is 1.
@ __p256_pinv → i { ^ 1 }

@ __ctl ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 } }

// A 16-limb magnitude, uninitialised. The hot routines below fill every
// limb through a raw `*i` before anyone reads one, so there is nothing to
// zero first — and unlike a push loop, filling by index costs no capacity
// check per limb.
@ __mag16 → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 16 )
    : b _l ( vec_set_len [i] v 16 )
    ^ v
}

// The same for an arbitrary limb count (the CIOS accumulator wants 18).
@ __magn i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : b _l ( vec_set_len [i] v n )
    ^ v
}

// ── field scratch ─────────────────────────────────────────────────────
// The modulus and the two temporaries every field operation needs, held
// for the length of a whole scalar multiply instead of being allocated
// and freed inside each one.
//
// This is where the allocator time went. `vec_with_cap` is TWO
// allocations — a 24-byte control block and the data buffer — so a
// Montgomery multiply that built `modp`, the accumulator, the difference
// and its result made eight, and one point addition performs about
// thirty field operations. A P-256 keygen was making ~164000
// allocations; now only each operation's RESULT is allocated.
//
// A scratch is created per scalar multiply and never shared between
// them, so there is no state to race over. Every routine below fills
// its scratch limbs completely before reading them, exactly as it did
// when they were fresh allocations.
: P256Scratch { ( Vec i ) modp ( Vec i ) t ( Vec i ) diff }

@ __p256_scr_new → P256Scratch {
    ^ @ P256Scratch { ( __p256_mod ) ( __magn 18 ) ( __mag16 ) }
}

@ __p256_scr_free P256Scratch s → v {
    ( vec_free [i] . s modp ) ( vec_free [i] . s t ) ( vec_free [i] . s diff )
}

// Limb access in the field routines goes through `*i` rather than
// `__ctl` / `vec_set`. Every one of these loops is fixed-count with an
// index the compiler can see is in range, so the bounds check the Vec
// accessors carry is provably redundant — but it is a real call, and a
// single Montgomery multiply makes about two thousand of them. That was
// 61% of a TLS handshake. Constant time is unaffected: the loops keep
// their fixed trip counts and stay branch-free in the data.

@ __zeros16 → ( Vec i ) {
    : ( Vec i ) v ( __mag16 )
    : *i q ( vec_data [i] v )
    : ~ i k 0
    ~ < k 16 { = . q k 0 = k + k 1 }
    ^ v
}

// Montgomery multiply: returns (a·b·R^-1) mod p as 16 fixed limbs. CIOS, all
// fixed-count loops, no data-dependent branch. a, b are 16-limb (< p).
@ p256ct_mul ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_mul_s scr a b )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_mul_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) modp . scr modp
    : i pinv ( __p256_pinv )
    // accumulator t has 18 limbs (n+2), starts zero.
    : ( Vec i ) t . scr t
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i tp ( vec_data [i] t )
    : *i pp ( vec_data [i] modp )
    : ~ i zz 0
    ~ < zz 18 { = . tp zz 0 = zz + zz 1 }
    : ~ i i 0
    ~ < i 16 {
        : i bi . bp i
        // t += a * b[i]
        : ~ i C 0
        : ~ i j 0
        ~ < j 16 {
            : i x + + . tp j * . ap j bi C
            = . tp j & x 65535
            = C >> x 16
            = j + j 1
        }
        : i x16 + . tp 16 C
        = . tp 16 & x16 65535
        = . tp 17 >> x16 16
        // m = t[0] * pinv mod 2^16 ; t = (t + m*p) / 2^16
        : i m & * . tp 0 pinv 65535
        : i x0 + . tp 0 * m . pp 0
        : ~ i C2 >> x0 16
        : ~ i j2 1
        ~ < j2 16 {
            : i y + + . tp j2 * m . pp j2 C2
            = . tp - j2 1 & y 65535
            = C2 >> y 16
            = j2 + j2 1
        }
        : i y16 + . tp 16 C2
        = . tp 15 & y16 65535
        = . tp 16 + . tp 17 >> y16 16
        = i + i 1
    }
    // t is 17 meaningful limbs (t[0..16]); value < 2p. Conditional subtract p.
    ^ ( __p256_cond_sub_p scr t )
}

// Given a 17-limb t in [0, 2p), return (t mod p) as 16 limbs, constant-time:
// compute t − p with borrow; if it underflows (t < p) keep t, else keep t−p.
// `modp` is passed in rather than rebuilt: every caller already holds it,
// and building it cost sixteen pushes into a fresh allocation on each of
// the ~3000 field operations a scalar multiply performs.
@ __p256_cond_sub_p P256Scratch scr ( Vec i ) t → ( Vec i ) {
    : ( Vec i ) diff . scr diff
    : *i tp ( vec_data [i] t )
    : *i pp ( vec_data [i] . scr modp )
    : *i dp ( vec_data [i] diff )
    : ~ i borrow 0
    : ~ i k 0
    ~ < k 16 {
        : ~ i d - - . tp k . pp k borrow
        ? < d 0 { = d + d 65536 = borrow 1 } { = borrow 0 }
        = . dp k d
        = k + k 1
    }
    // top limb t[16] minus the final borrow: if negative, t < p.
    : i topb - . tp 16 borrow
    // mask = 0xffff if (t >= p) i.e. topb >= 0, else 0 (keep t).
    : i tge & 1 ? >= topb 0 1 0
    : i mask & 65535 - 0 tge
    : i imask & 65535 - 0 - 1 tge
    : ( Vec i ) out ( __mag16 )
    : *i op ( vec_data [i] out )
    : ~ i j 0
    ~ < j 16 {
        = . op j | & mask . dp j & imask . tp j
        = j + j 1
    }
    ^ out
}

// (a + b) mod p, constant-time. a, b < p ⇒ a+b < 2p ⇒ one conditional sub.
@ p256ct_add ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_add_s scr a b )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_add_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    // The 18-limb accumulator doubles as the 17-limb sum.
    : ( Vec i ) t . scr t
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i tp ( vec_data [i] t )
    : ~ i carry 0
    : ~ i k 0
    ~ < k 16 {
        : i s + + . ap k . bp k carry
        = . tp k & s 65535
        = carry >> s 16
        = k + k 1
    }
    = . tp 16 carry
    ^ ( __p256_cond_sub_p scr t )
}

// (a − b) mod p, constant-time: a − b, and if it borrows add p back.
@ p256ct_sub ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_sub_s scr a b )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_sub_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) modp . scr modp
    : ( Vec i ) d . scr diff
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i pp ( vec_data [i] modp )
    : *i dp ( vec_data [i] d )
    : ~ i borrow 0
    : ~ i k 0
    ~ < k 16 {
        : ~ i x - - . ap k . bp k borrow
        ? < x 0 { = x + x 65536 = borrow 1 } { = borrow 0 }
        = . dp k x
        = k + k 1
    }
    // if borrow (a < b), add p (masked).
    : i mask & 65535 - 0 borrow
    : ( Vec i ) out ( __mag16 )
    : *i op ( vec_data [i] out )
    : ~ i c2 0
    : ~ i j 0
    ~ < j 16 {
        : i s + + . dp j & mask . pp j c2
        = . op j & s 65535
        = c2 >> s 16
        = j + j 1
    }
    ^ out
}

@ p256ct_sqr ( Vec i ) a → ( Vec i ) { ^ ( p256ct_mul a a ) }

@ p256ct_to_mont ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_to_mont_s scr a )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_to_mont_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) r2 ( __p256_r2 )
    : ( Vec i ) r ( __p256_mul_s scr a r2 )
    ( vec_free [i] r2 )
    ^ r
}

@ p256ct_from_mont ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_from_mont_s scr a )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_from_mont_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) one ( __p256_one )
    : ( Vec i ) r ( __p256_mul_s scr a one )
    ( vec_free [i] one )
    ^ r
}

// True iff a == 0 (constant-time OR of all limbs). a is a plain/Mont limb vec.
@ p256ct_is_zero ( Vec i ) a → b {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 16 { = acc | acc ( __ctl a k ) = k + k 1 }
    ^ == acc 0
}

// Montgomery 1 (= R mod p), the field identity in Montgomery form.
@ p256ct_one_mont → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_one_mont_s scr )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_one_mont_s P256Scratch scr → ( Vec i ) {
    : ( Vec i ) one ( __p256_one )
    : ( Vec i ) r ( __p256_to_mont_s scr one )
    ( vec_free [i] one )
    ^ r
}

// Modular inverse in Montgomery form: a^(p-2) mod p, via a fixed addition
// chain over montmul/montsqr. The exponent p−2 is a public constant, so the
// square/multiply schedule is data-independent. Input/output in Mont form;
// a^(p-2)·R ≡ a^-1·R (mod p). For a == 0 returns 0.
@ p256ct_inv ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_inv_s scr a )
    ( __p256_scr_free scr )
    ^ r
}

// 256 squarings and 256 multiplies of the Fermat chain, all off one scratch.
@ __p256_inv_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    // p-2 = ffffffff00000001000000000000000000000000fffffffffffffffffffffffd
    // Square-and-multiply, MSB→LSB, over the 256-bit exponent's limbs.
    : ( Vec i ) e ( __p256_pm2 )
    : ~ ( Vec i ) result ( __p256_one_mont_s scr )
    : ~ i bit 255
    ~ >= bit 0 {
        : ( Vec i ) sq ( __p256_mul_s scr result result )
        ( vec_free [i] result ) = result sq
        : i li / bit 16
        : i bp % bit 16
        : i b1 & 1 >> ( __ctl e li ) bp
        : ( Vec i ) prod ( __p256_mul_s scr result a )
        // constant-time select prod (if bit) else result
        : i mask & 65535 - 0 b1
        : i imask & 65535 - 0 - 1 b1
        : ( Vec i ) sel ( __p256_lmerge mask imask prod result )
        ( vec_free [i] prod ) ( vec_free [i] result )
        = result sel
        = bit - bit 1
    }
    ( vec_free [i] e )
    ^ result
}

// p − 2, little-endian 16-bit limbs.
@ __p256_pm2 → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 16 )
    ( vec_push [i] v 65533 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 )
    ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 0 ) ( vec_push [i] v 0 )
    ( vec_push [i] v 0 ) ( vec_push [i] v 0 ) ( vec_push [i] v 0 ) ( vec_push [i] v 0 )
    ( vec_push [i] v 1 ) ( vec_push [i] v 0 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 )
    ^ v
}

@ p256ct_free ( Vec i ) a → v { ( vec_free [i] a ) }

// ── constant-time P-256 point arithmetic (homogeneous projective) ──────
// Points are (X : Y : Z), x = X/Z, y = Y/Z, identity = (0 : 1 : 0); every
// coordinate is a 16-limb Montgomery field element. Addition uses the Renes–
// Costello–Batina COMPLETE formula (a = −3) — correct for ALL inputs incl.
// the identity and P = Q, with no branch — so the scalar-multiply ladder is
// fully constant-time (verified against `cryptography`'s P-256 in Python and
// cross-checked against the bigint reference). a / b3 are passed in Montgomery
// form (curve constants, computed once per scalar-mult).

: P256Pt { ( Vec i ) x ( Vec i ) y ( Vec i ) z }

@ p256pt_free P256Pt p → v {
    ( vec_free [i] . p x ) ( vec_free [i] . p y ) ( vec_free [i] . p z )
}

// a (= −3 mod p) and b3 (= 3·b mod p), plain (non-Montgomery) limbs.
@ __p256_a_plain → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 16 )
    ( vec_push [i] v 65532 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 )
    ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 0 ) ( vec_push [i] v 0 )
    ( vec_push [i] v 0 ) ( vec_push [i] v 0 ) ( vec_push [i] v 0 ) ( vec_push [i] v 0 )
    ( vec_push [i] v 1 ) ( vec_push [i] v 0 ) ( vec_push [i] v 65535 ) ( vec_push [i] v 65535 )
    ^ v
}

@ __p256_b3_plain → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 16 )
    ( vec_push [i] v 8418 ) ( vec_push [i] v 30583 ) ( vec_push [i] v 46266 ) ( vec_push [i] v 45930 )
    ( vec_push [i] v 4834 ) ( vec_push [i] v 25851 ) ( vec_push [i] v 5137 ) ( vec_push [i] v 12119 )
    ( vec_push [i] v 37941 ) ( vec_push [i] v 25545 ) ( vec_push [i] v 14336 ) ( vec_push [i] v 7107 )
    ( vec_push [i] v 48054 ) ( vec_push [i] v 65199 ) ( vec_push [i] v 41354 ) ( vec_push [i] v 4178 )
    ^ v
}

// Complete projective point addition, RCB Algorithm 4 (a = −3). All operands
// in Montgomery form; `am` = a, `b3m` = b3 in Montgomery form. Returns a fresh
// point. Mutable registers t0..t5 / X3,Y3,Z3 mirror the published register
// reuse; each reassignment frees the overwritten value.
@ p256ct_padd P256Scratch scr P256Pt P P256Pt Q ( Vec i ) am ( Vec i ) b3m → P256Pt {
    : ( Vec i ) X1 . P x : ( Vec i ) Y1 . P y : ( Vec i ) Z1 . P z
    : ( Vec i ) X2 . Q x : ( Vec i ) Y2 . Q y : ( Vec i ) Z2 . Q z
    : ~ ( Vec i ) t0 ( __p256_mul_s scr X1 X2 )
    : ~ ( Vec i ) t1 ( __p256_mul_s scr Y1 Y2 )
    : ~ ( Vec i ) t2 ( __p256_mul_s scr Z1 Z2 )
    : ~ ( Vec i ) t3 ( __p256_add_s scr X1 Y1 )
    : ~ ( Vec i ) t4 ( __p256_add_s scr X2 Y2 )
    : ( Vec i ) m6 ( __p256_mul_s scr t3 t4 ) ( vec_free [i] t3 ) = t3 m6
    : ( Vec i ) m7 ( __p256_add_s scr t0 t1 ) ( vec_free [i] t4 ) = t4 m7
    : ( Vec i ) m8 ( __p256_sub_s scr t3 t4 ) ( vec_free [i] t3 ) = t3 m8
    : ( Vec i ) m9 ( __p256_add_s scr X1 Z1 ) ( vec_free [i] t4 ) = t4 m9
    : ~ ( Vec i ) t5 ( __p256_add_s scr X2 Z2 )
    : ( Vec i ) m11 ( __p256_mul_s scr t4 t5 ) ( vec_free [i] t4 ) = t4 m11
    : ( Vec i ) m12 ( __p256_add_s scr t0 t2 ) ( vec_free [i] t5 ) = t5 m12
    : ( Vec i ) m13 ( __p256_sub_s scr t4 t5 ) ( vec_free [i] t4 ) = t4 m13
    : ( Vec i ) m14 ( __p256_add_s scr Y1 Z1 ) ( vec_free [i] t5 ) = t5 m14
    : ~ ( Vec i ) X3 ( __p256_add_s scr Y2 Z2 )
    : ( Vec i ) m16 ( __p256_mul_s scr t5 X3 ) ( vec_free [i] t5 ) = t5 m16
    : ( Vec i ) m17 ( __p256_add_s scr t1 t2 ) ( vec_free [i] X3 ) = X3 m17
    : ( Vec i ) m18 ( __p256_sub_s scr t5 X3 ) ( vec_free [i] t5 ) = t5 m18
    : ~ ( Vec i ) Z3 ( __p256_mul_s scr am t4 )
    : ( Vec i ) m20 ( __p256_mul_s scr b3m t2 ) ( vec_free [i] X3 ) = X3 m20
    : ( Vec i ) m21 ( __p256_add_s scr X3 Z3 ) ( vec_free [i] Z3 ) = Z3 m21
    : ( Vec i ) m22 ( __p256_sub_s scr t1 Z3 ) ( vec_free [i] X3 ) = X3 m22
    : ( Vec i ) m23 ( __p256_add_s scr t1 Z3 ) ( vec_free [i] Z3 ) = Z3 m23
    : ~ ( Vec i ) Y3 ( __p256_mul_s scr X3 Z3 )
    : ( Vec i ) m25 ( __p256_add_s scr t0 t0 ) ( vec_free [i] t1 ) = t1 m25
    : ( Vec i ) m26 ( __p256_add_s scr t1 t0 ) ( vec_free [i] t1 ) = t1 m26
    : ( Vec i ) m27 ( __p256_mul_s scr am t2 ) ( vec_free [i] t2 ) = t2 m27
    : ( Vec i ) m28 ( __p256_mul_s scr b3m t4 ) ( vec_free [i] t4 ) = t4 m28
    : ( Vec i ) m29 ( __p256_add_s scr t1 t2 ) ( vec_free [i] t1 ) = t1 m29
    : ( Vec i ) m30 ( __p256_sub_s scr t0 t2 ) ( vec_free [i] t2 ) = t2 m30
    : ( Vec i ) m31 ( __p256_mul_s scr am t2 ) ( vec_free [i] t2 ) = t2 m31
    : ( Vec i ) m32 ( __p256_add_s scr t4 t2 ) ( vec_free [i] t4 ) = t4 m32
    : ( Vec i ) m33 ( __p256_mul_s scr t1 t4 ) ( vec_free [i] t0 ) = t0 m33
    : ( Vec i ) m34 ( __p256_add_s scr Y3 t0 ) ( vec_free [i] Y3 ) = Y3 m34
    : ( Vec i ) m35 ( __p256_mul_s scr t5 t4 ) ( vec_free [i] t0 ) = t0 m35
    : ( Vec i ) m36 ( __p256_mul_s scr t3 X3 ) ( vec_free [i] X3 ) = X3 m36
    : ( Vec i ) m37 ( __p256_sub_s scr X3 t0 ) ( vec_free [i] X3 ) = X3 m37
    : ( Vec i ) m38 ( __p256_mul_s scr t3 t1 ) ( vec_free [i] t0 ) = t0 m38
    : ( Vec i ) m39 ( __p256_mul_s scr t5 Z3 ) ( vec_free [i] Z3 ) = Z3 m39
    : ( Vec i ) m40 ( __p256_add_s scr Z3 t0 ) ( vec_free [i] Z3 ) = Z3 m40
    ( vec_free [i] t0 ) ( vec_free [i] t1 ) ( vec_free [i] t2 )
    ( vec_free [i] t3 ) ( vec_free [i] t4 ) ( vec_free [i] t5 )
    ^ @ P256Pt { X3 Y3 Z3 }
}

// Constant-time select between two points (each coordinate via masked merge).
@ p256ct_pt_select i bit P256Pt a P256Pt b → P256Pt {
    : i mask & 65535 - 0 bit
    : i imask & 65535 - 0 - 1 bit
    ^ @ P256Pt {
        ( __p256_lmerge mask imask . a x . b x )
        ( __p256_lmerge mask imask . a y . b y )
        ( __p256_lmerge mask imask . a z . b z )
    }
}

@ __p256_lmerge i mask i imask ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( __mag16 )
    : *i op ( vec_data [i] out )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : ~ i k 0
    ~ < k 16 { = . op k | & mask . ap k & imask . bp k = k + k 1 }
    ^ out
}

@ p256ct_pt_clone P256Pt p → P256Pt {
    ^ @ P256Pt { ( __mag16_clone . p x ) ( __mag16_clone . p y ) ( __mag16_clone . p z ) }
}

@ __mag16_clone ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( __mag16 )
    : *i op ( vec_data [i] out )
    : *i ap ( vec_data [i] a )
    : ~ i k 0
    ~ < k 16 { = . op k . ap k = k + k 1 }
    ^ out
}

// Identity point (0 : 1 : 0) in Montgomery form.
@ p256ct_identity → P256Pt {
    : ( Vec i ) z0 ( __zeros16 )
    : ( Vec i ) one ( p256ct_one_mont )
    : ( Vec i ) z0b ( __zeros16 )
    ^ @ P256Pt { z0 one z0b }
}

// Scalar × affine base point → affine (x, y) as two 32-byte big-endian vecs.
// `kbytes` is the scalar, big-endian; bx/by are the base point's affine
// coordinates as 16-limb plain (non-Montgomery) field elements. Branchless
// Coron always-add ladder over the RCB complete addition: every bit doubles
// and adds, then a constant-time point select keeps the add iff the bit set.
// Returns the all-zero 64 bytes for the identity result.
@ p256ct_scalarmult ( Vec u ) kbytes ( Vec i ) bx ( Vec i ) by → ( Vec u ) {
    // One scratch for the whole ladder — see P256Scratch. Every field
    // operation below borrows its modulus and temporaries from here.
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) aplain ( __p256_a_plain )
    : ( Vec i ) am ( __p256_to_mont_s scr aplain )
    ( vec_free [i] aplain )
    : ( Vec i ) b3plain ( __p256_b3_plain )
    : ( Vec i ) b3m ( __p256_to_mont_s scr b3plain )
    ( vec_free [i] b3plain )
    // base in Montgomery projective form (Z = 1).
    : ( Vec i ) bxm ( __p256_to_mont_s scr bx )
    : ( Vec i ) bym ( __p256_to_mont_s scr by )
    : ( Vec i ) bzm ( __p256_one_mont_s scr )
    : P256Pt base @ P256Pt { bxm bym bzm }
    : ~ P256Pt acc ( p256ct_identity )
    : i nbytes ( vec_len [u] kbytes )
    : i nbits * nbytes 8
    // MSB-first: pos = 0 is byte 0 / bit 7 (most significant), matching the
    // big-endian scalar and the bigint reference ladder.
    : ~ i pos 0
    ~ < pos nbits {
        : i byteidx / pos 8
        : i bitpos - 7 % pos 8
        : i bv ?? ( vec_get [u] kbytes byteidx ) { T b → # i b F _ → 0 }
        : i bit & 1 >> bv bitpos
        : P256Pt dbl ( p256ct_padd scr acc acc am b3m )
        ( p256pt_free acc ) = acc dbl
        : P256Pt added ( p256ct_padd scr acc base am b3m )
        : P256Pt sel ( p256ct_pt_select bit added acc )
        ( p256pt_free added ) ( p256pt_free acc ) = acc sel
        = pos + pos 1
    }
    // affine: x = X/Z, y = Y/Z (de-Montgomery via inverse).
    : ( Vec i ) zinv ( __p256_inv_s scr . acc z )
    : ( Vec i ) xm ( __p256_mul_s scr . acc x zinv )
    : ( Vec i ) ym ( __p256_mul_s scr . acc y zinv )
    : ( Vec i ) xp ( __p256_from_mont_s scr xm )
    : ( Vec i ) yp ( __p256_from_mont_s scr ym )
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( __p256_limbs_to_be out xp )
    ( __p256_limbs_to_be out yp )
    ( p256pt_free base ) ( p256pt_free acc )
    ( vec_free [i] am ) ( vec_free [i] b3m )
    ( vec_free [i] zinv ) ( vec_free [i] xm ) ( vec_free [i] ym )
    ( vec_free [i] xp ) ( vec_free [i] yp )
    ( __p256_scr_free scr )
    ^ out
}

// Append a 16-limb field element as 32 big-endian bytes to `out`.
@ __p256_limbs_to_be ( Vec u ) out ( Vec i ) v → v {
    : ~ i k 15
    ~ >= k 0 {
        : i lk ( __ctl v k )
        ( vec_push [u] out # u & >> lk 8 255 )
        ( vec_push [u] out # u & lk 255 )
        = k - k 1
    }
}
