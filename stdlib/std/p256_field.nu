// stdlib/std/p256_field.nu — constant-time GF(p) arithmetic for NIST P-256.
//
// A dedicated FIXED-WIDTH field: every element is exactly 8 little-endian
// 32-bit limbs (256 bits), NEVER normalized/trimmed, so no operation's
// duration depends on the value. This is the constant-time core the generic
// std/bigint.nu cannot be (it trims leading-zero limbs → operand-time-
// dependent). Multiplication is Montgomery CIOS; add/sub use a constant-time
// conditional ±p; inversion is a fixed Fermat chain (a^(p-2)). All loops are
// fixed-count and branch-free in the data.
//
// The limb radix is 2^32 and the CIOS intermediates are `u64`: a 32×32 → 64
// product is one machine multiply, so the schoolbook body is 8×8 = 64 of
// them per multiply instead of the 16×16 = 256 the old 16-bit radix needed,
// and the interleaved Montgomery reduction shrinks the same way. Every limb
// is stored masked to 32 bits, so reading one back as `u64` is exact.
//
// Every operation comes in two forms: an allocating `p256ct_*` for callers
// that just want a value, and a `_d` worker that WRITES INTO a destination
// the caller already owns. The ladder uses only the `_d` form, so a whole
// scalar multiply allocates a fixed handful of limb vectors instead of one
// per field operation (see p256ct_scalarmult).
//
// Elements live in Montgomery form (ā = a·R mod p, R = 2^256) so that
// p256ct_mul ā b̄ = (a·b)·R mod p stays in form. Convert in with
// p256ct_to_mont, out with p256ct_from_mont. Used by the secret-scalar P-256
// point multiply (ECDSA nonce / ECDH); verify keeps the public bigint path.

$ `stdlib/core/vec.nu`

// p = 2^256 − 2^224 + 2^192 + 2^96 − 1, little-endian 32-bit limbs.
@ __p256_mod → ( Vec i ) {
    // Filled by index, not pushed: a push carries a capacity check the
    // fixed eight limbs do not need.
    : ( Vec i ) v ( __mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 0xFFFFFFFF = . q 1 0xFFFFFFFF = . q 2 0xFFFFFFFF = . q 3 0
    = . q 4 0 = . q 5 0 = . q 6 1 = . q 7 0xFFFFFFFF
    ^ v
}

// R^2 mod p (= 2^512 mod p) — multiply by this (Montgomery) to enter the domain.
@ __p256_r2 → ( Vec i ) {
    : ( Vec i ) v ( __mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 3 = . q 1 0 = . q 2 0xFFFFFFFF = . q 3 0xFFFFFFFB
    = . q 4 0xFFFFFFFE = . q 5 0xFFFFFFFF = . q 6 0xFFFFFFFD = . q 7 4
    ^ v
}

// 1 in plain (non-Montgomery) form: [1, 0, …]. Montgomery-multiplying by this
// leaves the domain (montmul(ā, 1) = a).
@ __p256_one → ( Vec i ) {
    : ( Vec i ) v ( __mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 1 = . q 1 0 = . q 2 0 = . q 3 0
    = . q 4 0 = . q 5 0 = . q 6 0 = . q 7 0
    ^ v
}

// The Montgomery constant -p^-1 mod 2^32 is 1, because p ≡ −1 (mod 2^32).
// It is not a function any more: __p256_mul_d folds it (and the whole
// modulus) into the reduction as shifts — see there.

@ __ctl ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 } }

// An 8-limb magnitude, uninitialised. The hot routines below fill every
// limb through a raw `*i` before anyone reads one, so there is nothing to
// zero first — and unlike a push loop, filling by index costs no capacity
// check per limb.
@ __mag8 → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 8 )
    : b _l ( vec_set_len [i] v 8 )
    ^ v
}

// The same for an arbitrary limb count (the CIOS accumulator wants 10).
@ __magn i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : b _l ( vec_set_len [i] v n )
    ^ v
}

// ── field scratch ─────────────────────────────────────────────────────
// Every temporary a scalar multiply needs, allocated once and held for the
// whole ladder: the modulus, the CIOS accumulator and difference, the six
// registers RCB point addition works in, and one spare for the inversion
// chain.
//
// This is where the allocator time went. `vec_with_cap` is TWO
// allocations — a 24-byte control block and the data buffer — and a P-256
// keygen performs roughly three thousand field operations, so allocating
// even one result per operation cost ~44000 allocations. With the `_d`
// workers writing into these registers, the ladder allocates NOTHING per
// iteration; a keygen now makes about thirty allocations in total.
//
// A scratch is created per scalar multiply and never shared between them,
// so there is no state to race over, and no `_d` worker calls another that
// wants the same register (the point layer owns g0..g5, the field layer
// owns t/diff, the inversion chain owns gp).
: P256Scratch {
    ( Vec i ) modp ( Vec i ) t ( Vec i ) diff
    ( Vec i ) g0 ( Vec i ) g1 ( Vec i ) g2
    ( Vec i ) g3 ( Vec i ) g4 ( Vec i ) g5
    ( Vec i ) gp
}

@ __p256_scr_new → P256Scratch {
    ^ @ P256Scratch {
        ( __p256_mod ) ( __magn 10 ) ( __mag8 )
        ( __mag8 ) ( __mag8 ) ( __mag8 )
        ( __mag8 ) ( __mag8 ) ( __mag8 )
        ( __mag8 )
    }
}

@ __p256_scr_free P256Scratch s → v {
    ( vec_free [i] . s modp ) ( vec_free [i] . s t ) ( vec_free [i] . s diff )
    ( vec_free [i] . s g0 ) ( vec_free [i] . s g1 ) ( vec_free [i] . s g2 )
    ( vec_free [i] . s g3 ) ( vec_free [i] . s g4 ) ( vec_free [i] . s g5 )
    ( vec_free [i] . s gp )
}

// Limb access in the field routines goes through `*i` rather than
// `__ctl` / `vec_set`. Every one of these loops is fixed-count with an
// index the compiler can see is in range, so the bounds check the Vec
// accessors carry is provably redundant — but it is a real call, and a
// single Montgomery multiply makes about two thousand of them. That was
// 61% of a TLS handshake. Constant time is unaffected: the loops keep
// their fixed trip counts and stay branch-free in the data.

@ __zeros8 → ( Vec i ) {
    : ( Vec i ) v ( __mag8 )
    : *i q ( vec_data [i] v )
    : ~ i k 0
    ~ < k 8 { = . q k 0 = k + k 1 }
    ^ v
}

// ── aliasing ──────────────────────────────────────────────────────────
// Every `_d` worker below may be called with `dst` aliasing any of its
// sources. That is safe by construction, not by luck: each one reads all
// of its operands into the scratch accumulator (`t` / `diff`) FIRST and
// only then writes `dst`, and the elementwise mergers read and write the
// same index in the same step. `__p256_inv_d` is the one exception —
// its `dst` must not alias `a`, and its own comment says so.

// Montgomery multiply: returns (a·b·R^-1) mod p as 8 fixed limbs. CIOS, all
// fixed-count loops, no data-dependent branch. a, b are 8-limb (< p).
@ p256ct_mul ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_mul_s scr a b )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_mul_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( __mag8 )
    ( __p256_mul_d scr out a b )
    ^ out
}

// CIOS, radix 2^32. Each accumulator word stays below 2^32 and every
// intermediate `t[j] + a[j]·b[i] + C` is bounded by
// (2^32−1) + (2^32−1)^2 + (2^32−1) = 2^64 − 1, so a `u64` holds it exactly
// — that bound is what makes this radix the largest one that needs no
// double-word carry.
@ __p256_mul_d P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    // accumulator t has 10 limbs (n+2), starts zero.
    : ( Vec i ) t . scr t
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i tp ( vec_data [i] t )
    : ~ i zz 0
    ~ < zz 10 { = . tp zz 0 = zz + zz 1 }
    : ~ i i 0
    ~ < i 8 {
        : u64 bi # u64 . bp i
        // t += a * b[i]
        : ~ u64 C 0
        : ~ i j 0
        ~ < j 8 {
            : u64 x + + # u64 . tp j * # u64 . ap j bi C
            = . tp j # i & x 0xFFFFFFFF
            = C >> x 32
            = j + j 1
        }
        : u64 x8 + # u64 . tp 8 C
        = . tp 8 # i & x8 0xFFFFFFFF
        = . tp 9 # i >> x8 32
        // t = (t + m·p) / 2^32, where m = t[0]·pinv mod 2^32.
        //
        // NOT A SINGLE MULTIPLY: pinv is 1, so m is just t[0], and
        // p = [2^32−1, 2^32−1, 2^32−1, 0, 0, 0, 1, 2^32−1] — every
        // partial product m·p[j] is a shift, a zero, or m itself. That
        // is half of this routine's multiplies gone, and it is the whole
        // reason a Montgomery-friendly prime is chosen with this shape.
        : u64 m # u64 . tp 0
        : u64 mp << m 32  // m·(2^32−1) = mp − m
        // j=0: t[0] + (mp − m) = mp, since m IS t[0] — low word zero
        //      (as the reduction requires) and carry m.
        // j=1,2: t[j] + (mp − m) + m = t[j] + mp — the limb falls
        //      through unchanged and the carry stays m.
        = . tp 0 . tp 1
        = . tp 1 . tp 2
        // j=3,4,5: p[j] = 0.
        : u64 y3 + # u64 . tp 3 m
        = . tp 2 # i & y3 0xFFFFFFFF
        : ~ u64 C2 >> y3 32
        : u64 y4 + # u64 . tp 4 C2
        = . tp 3 # i & y4 0xFFFFFFFF
        = C2 >> y4 32
        : u64 y5 + # u64 . tp 5 C2
        = . tp 4 # i & y5 0xFFFFFFFF
        = C2 >> y5 32
        // j=6: p[6] = 1.
        : u64 y6 + + # u64 . tp 6 m C2
        = . tp 5 # i & y6 0xFFFFFFFF
        = C2 >> y6 32
        // j=7: p[7] = 2^32−1 again.
        : u64 y7 + + # u64 . tp 7 - mp m C2
        = . tp 6 # i & y7 0xFFFFFFFF
        = C2 >> y7 32
        : u64 y8 + # u64 . tp 8 C2
        = . tp 7 # i & y8 0xFFFFFFFF
        = . tp 8 + . tp 9 # i >> y8 32
        = i + i 1
    }
    // t is 9 meaningful limbs (t[0..8]); value < 2p. Conditional subtract p.
    ( __p256_cond_sub_d scr dst t )
}

// Given a 9-limb t in [0, 2p), write (t mod p) as 8 limbs into dst,
// constant-time: compute t − p with borrow; if it underflows (t < p) keep
// t, else keep t−p. `modp` comes from the scratch rather than being
// rebuilt: every caller already holds it, and building it cost eight
// stores into a fresh allocation on each of the ~3000 field operations a
// scalar multiply performs.
@ __p256_cond_sub_d P256Scratch scr ( Vec i ) dst ( Vec i ) t → v {
    : ( Vec i ) diff . scr diff
    : *i tp ( vec_data [i] t )
    : *i pp ( vec_data [i] . scr modp )
    : *i dp ( vec_data [i] diff )
    : ~ i borrow 0
    : ~ i k 0
    ~ < k 8 {
        : ~ i d - - . tp k . pp k borrow
        ? < d 0 { = d + d 4294967296 = borrow 1 } { = borrow 0 }
        = . dp k d
        = k + k 1
    }
    // top limb t[8] minus the final borrow: if negative, t < p.
    : i topb - . tp 8 borrow
    // mask = 0xffffffff if (t >= p) i.e. topb >= 0, else 0 (keep t).
    : i tge & 1 ? >= topb 0 1 0
    : i mask & 0xFFFFFFFF - 0 tge
    : i imask & 0xFFFFFFFF - 0 - 1 tge
    : *i op ( vec_data [i] dst )
    : ~ i j 0
    ~ < j 8 {
        = . op j | & mask . dp j & imask . tp j
        = j + j 1
    }
}

// (a + b) mod p, constant-time. a, b < p ⇒ a+b < 2p ⇒ one conditional sub.
@ p256ct_add ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_add_s scr a b )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_add_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( __mag8 )
    ( __p256_add_d scr out a b )
    ^ out
}

@ __p256_add_d P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    // The 10-limb accumulator doubles as the 9-limb sum.
    : ( Vec i ) t . scr t
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i tp ( vec_data [i] t )
    : ~ i carry 0
    : ~ i k 0
    ~ < k 8 {
        : i s + + . ap k . bp k carry
        = . tp k & s 0xFFFFFFFF
        = carry >> s 32
        = k + k 1
    }
    = . tp 8 carry
    ( __p256_cond_sub_d scr dst t )
}

// (a − b) mod p, constant-time: a − b, and if it borrows add p back.
@ p256ct_sub ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_sub_s scr a b )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_sub_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( __mag8 )
    ( __p256_sub_d scr out a b )
    ^ out
}

@ __p256_sub_d P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : ( Vec i ) modp . scr modp
    : ( Vec i ) d . scr diff
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : *i pp ( vec_data [i] modp )
    : *i dp ( vec_data [i] d )
    : ~ i borrow 0
    : ~ i k 0
    ~ < k 8 {
        : ~ i x - - . ap k . bp k borrow
        ? < x 0 { = x + x 4294967296 = borrow 1 } { = borrow 0 }
        = . dp k x
        = k + k 1
    }
    // if borrow (a < b), add p (masked).
    : i mask & 0xFFFFFFFF - 0 borrow
    : *i op ( vec_data [i] dst )
    : ~ i c2 0
    : ~ i j 0
    ~ < j 8 {
        : i s + + . dp j & mask . pp j c2
        = . op j & s 0xFFFFFFFF
        = c2 >> s 32
        = j + j 1
    }
}

@ p256ct_sqr ( Vec i ) a → ( Vec i ) { ^ ( p256ct_mul a a ) }

@ p256ct_to_mont ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_to_mont_s scr a )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_to_mont_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( __mag8 )
    ( __p256_to_mont_d scr out a )
    ^ out
}

@ __p256_to_mont_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    : ( Vec i ) r2 ( __p256_r2 )
    ( __p256_mul_d scr dst a r2 )
    ( vec_free [i] r2 )
}

@ p256ct_from_mont ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) r ( __p256_from_mont_s scr a )
    ( __p256_scr_free scr )
    ^ r
}

@ __p256_from_mont_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( __mag8 )
    ( __p256_from_mont_d scr out a )
    ^ out
}

@ __p256_from_mont_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    : ( Vec i ) one ( __p256_one )
    ( __p256_mul_d scr dst a one )
    ( vec_free [i] one )
}

// True iff a == 0 (constant-time OR of all limbs). a is a plain/Mont limb vec.
@ p256ct_is_zero ( Vec i ) a → b {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 8 { = acc | acc ( __ctl a k ) = k + k 1 }
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
    : ( Vec i ) out ( __mag8 )
    ( __p256_one_mont_d scr out )
    ^ out
}

@ __p256_one_mont_d P256Scratch scr ( Vec i ) dst → v {
    : ( Vec i ) one ( __p256_one )
    ( __p256_to_mont_d scr dst one )
    ( vec_free [i] one )
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

@ __p256_inv_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( __mag8 )
    ( __p256_inv_d scr out a )
    ^ out
}

// 256 squarings and 256 multiplies of the Fermat chain, all in place off
// one scratch. UNLIKE the other `_d` workers, `dst` must NOT alias `a`:
// `a` is read on every iteration, and `dst` is the running accumulator.
@ __p256_inv_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    // p-2 = ffffffff00000001000000000000000000000000fffffffffffffffffffffffd
    // Square-and-multiply, MSB→LSB, over the 256-bit exponent's limbs.
    : ( Vec i ) e ( __p256_pm2 )
    : ( Vec i ) prod . scr gp
    ( __p256_one_mont_d scr dst )
    : ~ i bit 255
    ~ >= bit 0 {
        ( __p256_mul_d scr dst dst dst )
        : i li / bit 32
        : i bp % bit 32
        : i b1 & 1 >> ( __ctl e li ) bp
        ( __p256_mul_d scr prod dst a )
        // constant-time select prod (if bit) else the running value
        : i mask & 0xFFFFFFFF - 0 b1
        : i imask & 0xFFFFFFFF - 0 - 1 b1
        ( __p256_lmerge_d dst mask imask prod dst )
        = bit - bit 1
    }
    ( vec_free [i] e )
}

// p − 2, little-endian 32-bit limbs.
@ __p256_pm2 → ( Vec i ) {
    : ( Vec i ) v ( __mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 0xFFFFFFFD = . q 1 0xFFFFFFFF = . q 2 0xFFFFFFFF = . q 3 0
    = . q 4 0 = . q 5 0 = . q 6 1 = . q 7 0xFFFFFFFF
    ^ v
}

@ p256ct_free ( Vec i ) a → v { ( vec_free [i] a ) }

// ── constant-time P-256 point arithmetic (homogeneous projective) ──────
// Points are (X : Y : Z), x = X/Z, y = Y/Z, identity = (0 : 1 : 0); every
// coordinate is an 8-limb Montgomery field element. Addition uses the Renes–
// Costello–Batina COMPLETE formula (a = −3) — correct for ALL inputs incl.
// the identity and P = Q, with no branch — so the scalar-multiply ladder is
// fully constant-time (verified against `cryptography`'s P-256 in Python and
// cross-checked against the bigint reference). a / b3 are passed in Montgomery
// form (curve constants, computed once per scalar-mult).

: P256Pt { ( Vec i ) x ( Vec i ) y ( Vec i ) z }

@ p256pt_free P256Pt p → v {
    ( vec_free [i] . p x ) ( vec_free [i] . p y ) ( vec_free [i] . p z )
}

// An uninitialised point (three 8-limb magnitudes) — a ladder register.
@ __p256_pt_mag → P256Pt {
    ^ @ P256Pt { ( __mag8 ) ( __mag8 ) ( __mag8 ) }
}

// a (= −3 mod p) and b3 (= 3·b mod p), plain (non-Montgomery) limbs.
@ __p256_a_plain → ( Vec i ) {
    : ( Vec i ) v ( __mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 0xFFFFFFFC = . q 1 0xFFFFFFFF = . q 2 0xFFFFFFFF = . q 3 0
    = . q 4 0 = . q 5 0 = . q 6 1 = . q 7 0xFFFFFFFF
    ^ v
}

@ __p256_b3_plain → ( Vec i ) {
    : ( Vec i ) v ( __mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 0x777720E2 = . q 1 0xB36AB4BA = . q 2 0x64FB12E2 = . q 3 0x2F571411
    = . q 4 0x63C99435 = . q 5 0x1BC33800 = . q 6 0xFEAFBBB6 = . q 7 0x1052A18A
    ^ v
}

// Complete projective point addition, RCB Algorithm 4 (a = −3). All operands
// in Montgomery form; `am` = a, `b3m` = b3 in Montgomery form.
@ p256ct_padd P256Scratch scr P256Pt P P256Pt Q ( Vec i ) am ( Vec i ) b3m → P256Pt {
    : P256Pt out ( __p256_pt_mag )
    ( p256ct_padd_d scr out P Q am b3m )
    ^ out
}

// The same, into a caller-owned destination. `dst` MAY be P and/or Q: the
// forty steps below are the published register schedule, and in it X3 is
// first written at step 15 (after the last read of X1 at step 9 and of X2
// at step 10), Y3 at step 24 and Z3 at step 19 (both after the last reads
// of Y1/Y2/Z1/Z2 at steps 14–15). The six working registers come from the
// scratch, so a point addition allocates nothing at all.
@ p256ct_padd_d P256Scratch scr P256Pt dst P256Pt P P256Pt Q ( Vec i ) am ( Vec i ) b3m → v {
    : ( Vec i ) X1 . P x : ( Vec i ) Y1 . P y : ( Vec i ) Z1 . P z
    : ( Vec i ) X2 . Q x : ( Vec i ) Y2 . Q y : ( Vec i ) Z2 . Q z
    : ( Vec i ) X3 . dst x : ( Vec i ) Y3 . dst y : ( Vec i ) Z3 . dst z
    : ( Vec i ) t0 . scr g0 : ( Vec i ) t1 . scr g1 : ( Vec i ) t2 . scr g2
    : ( Vec i ) t3 . scr g3 : ( Vec i ) t4 . scr g4 : ( Vec i ) t5 . scr g5
    ( __p256_mul_d scr t0 X1 X2 )  //  1
    ( __p256_mul_d scr t1 Y1 Y2 )  //  2
    ( __p256_mul_d scr t2 Z1 Z2 )  //  3
    ( __p256_add_d scr t3 X1 Y1 )  //  4
    ( __p256_add_d scr t4 X2 Y2 )  //  5
    ( __p256_mul_d scr t3 t3 t4 )  //  6
    ( __p256_add_d scr t4 t0 t1 )  //  7
    ( __p256_sub_d scr t3 t3 t4 )  //  8
    ( __p256_add_d scr t4 X1 Z1 )  //  9
    ( __p256_add_d scr t5 X2 Z2 )  // 10
    ( __p256_mul_d scr t4 t4 t5 )  // 11
    ( __p256_add_d scr t5 t0 t2 )  // 12
    ( __p256_sub_d scr t4 t4 t5 )  // 13
    ( __p256_add_d scr t5 Y1 Z1 )  // 14
    ( __p256_add_d scr X3 Y2 Z2 )  // 15
    ( __p256_mul_d scr t5 t5 X3 )  // 16
    ( __p256_add_d scr X3 t1 t2 )  // 17
    ( __p256_sub_d scr t5 t5 X3 )  // 18
    ( __p256_mul_d scr Z3 am t4 )  // 19
    ( __p256_mul_d scr X3 b3m t2 )  // 20
    ( __p256_add_d scr Z3 X3 Z3 )  // 21
    ( __p256_sub_d scr X3 t1 Z3 )  // 22
    ( __p256_add_d scr Z3 t1 Z3 )  // 23
    ( __p256_mul_d scr Y3 X3 Z3 )  // 24
    ( __p256_add_d scr t1 t0 t0 )  // 25
    ( __p256_add_d scr t1 t1 t0 )  // 26
    ( __p256_mul_d scr t2 am t2 )  // 27
    ( __p256_mul_d scr t4 b3m t4 )  // 28
    ( __p256_add_d scr t1 t1 t2 )  // 29
    ( __p256_sub_d scr t2 t0 t2 )  // 30
    ( __p256_mul_d scr t2 am t2 )  // 31
    ( __p256_add_d scr t4 t4 t2 )  // 32
    ( __p256_mul_d scr t0 t1 t4 )  // 33
    ( __p256_add_d scr Y3 Y3 t0 )  // 34
    ( __p256_mul_d scr t0 t5 t4 )  // 35
    ( __p256_mul_d scr X3 t3 X3 )  // 36
    ( __p256_sub_d scr X3 X3 t0 )  // 37
    ( __p256_mul_d scr t0 t3 t1 )  // 38
    ( __p256_mul_d scr Z3 t5 Z3 )  // 39
    ( __p256_add_d scr Z3 Z3 t0 )  // 40
}

// Constant-time select between two points (each coordinate via masked merge).
@ p256ct_pt_select i bit P256Pt a P256Pt b → P256Pt {
    : P256Pt out ( __p256_pt_mag )
    ( p256ct_pt_select_d out bit a b )
    ^ out
}

// `dst` may alias `a` or `b`: the merge reads and writes one limb index at
// a time.
@ p256ct_pt_select_d P256Pt dst i bit P256Pt a P256Pt b → v {
    : i mask & 0xFFFFFFFF - 0 bit
    : i imask & 0xFFFFFFFF - 0 - 1 bit
    ( __p256_lmerge_d . dst x mask imask . a x . b x )
    ( __p256_lmerge_d . dst y mask imask . a y . b y )
    ( __p256_lmerge_d . dst z mask imask . a z . b z )
}

@ __p256_lmerge_d ( Vec i ) dst i mask i imask ( Vec i ) a ( Vec i ) b → v {
    : *i op ( vec_data [i] dst )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : ~ i k 0
    ~ < k 8 { = . op k | & mask . ap k & imask . bp k = k + k 1 }
}

@ p256ct_pt_clone P256Pt p → P256Pt {
    ^ @ P256Pt { ( __mag8_clone . p x ) ( __mag8_clone . p y ) ( __mag8_clone . p z ) }
}

@ __mag8_clone ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( __mag8 )
    ( __p256_copy_d out a )
    ^ out
}

@ __p256_copy_d ( Vec i ) dst ( Vec i ) a → v {
    : *i op ( vec_data [i] dst )
    : *i ap ( vec_data [i] a )
    : ~ i k 0
    ~ < k 8 { = . op k . ap k = k + k 1 }
}

// Identity point (0 : 1 : 0) in Montgomery form.
@ p256ct_identity → P256Pt {
    : ( Vec i ) z0 ( __zeros8 )
    : ( Vec i ) one ( p256ct_one_mont )
    : ( Vec i ) z0b ( __zeros8 )
    ^ @ P256Pt { z0 one z0b }
}

// Set an existing point to the identity, off the caller's scratch.
@ __p256_set_identity_d P256Scratch scr P256Pt dst → v {
    : *i xp ( vec_data [i] . dst x )
    : *i zp ( vec_data [i] . dst z )
    : ~ i k 0
    ~ < k 8 { = . xp k 0 = . zp k 0 = k + k 1 }
    ( __p256_one_mont_d scr . dst y )
}

@ __p256_pt_copy_d P256Pt dst P256Pt a → v {
    ( __p256_copy_d . dst x . a x )
    ( __p256_copy_d . dst y . a y )
    ( __p256_copy_d . dst z . a z )
}

// ── the window table ──────────────────────────────────────────────────
// Sixteen projective multiples of the base point, 0·B … 15·B, in one flat
// limb vector: entry d occupies [d·24, d·24+24) as x‖y‖z. Flat because the
// constant-time read below has to walk EVERY entry, and a straight run of
// limbs is what that walk wants.

@ __p256_tbl_put ( Vec i ) tbl i d P256Pt p → v {
    : *i tp ( vec_data [i] tbl )
    : *i xp ( vec_data [i] . p x )
    : *i yp ( vec_data [i] . p y )
    : *i zp ( vec_data [i] . p z )
    : i base * d 24
    : ~ i k 0
    ~ < k 8 {
        = . tp + base k . xp k
        = . tp + + base 8 k . yp k
        = . tp + + base 16 k . zp k
        = k + k 1
    }
}

// Read entry `digit` into `dst`. `digit` is four bits of the SECRET scalar,
// so this must not become an indexed load: it reads all sixteen entries,
// every time, and merges each one under a mask that is 0xffffffff exactly
// when d == digit. The mask is arithmetic, not a comparison — `d ^ digit`
// is zero only on a match, and subtracting one from zero borrows all the
// way into the top bit, which nothing else can set for a 4-bit value. No
// branch, and the address stream is identical for every possible digit.
@ __p256_tbl_get_d P256Pt dst ( Vec i ) tbl i digit → v {
    : *i tp ( vec_data [i] tbl )
    : *i xp ( vec_data [i] . dst x )
    : *i yp ( vec_data [i] . dst y )
    : *i zp ( vec_data [i] . dst z )
    : ~ i k 0
    ~ < k 8 { = . xp k 0 = . yp k 0 = . zp k 0 = k + k 1 }
    : ~ i d 0
    ~ < d 16 {
        : u64 z ^^ # u64 d # u64 digit
        : i mask & 0xFFFFFFFF - 0 # i >> - z 1 63
        : i base * d 24
        : ~ i j 0
        ~ < j 8 {
            = . xp j | . xp j & mask . tp + base j
            = . yp j | . yp j & mask . tp + + base 8 j
            = . zp j | . zp j & mask . tp + + base 16 j
            = j + j 1
        }
        = d + d 1
    }
}

// Scalar × affine base point → affine (x, y) as two 32-byte big-endian vecs.
// `kbytes` is the scalar, big-endian; bx/by are the base point's affine
// coordinates as 8-limb plain (non-Montgomery) field elements. Returns the
// all-zero 64 bytes for the identity result.
//
// FIXED 4-BIT WINDOW over the RCB complete addition. The scalar is consumed
// a nibble at a time, most significant first: four doublings shift the
// accumulator up by sixteen, then one addition brings in digit·B read out
// of the window table. That is 4·64 + 64 + 14 = 334 point additions for a
// 32-byte scalar, where the bit-at-a-time always-add ladder it replaces
// needed 512 — and the table walk that buys it costs about 4% of one
// addition per window.
//
// Constant-time on the same terms as before, and for the same reasons:
//   * the step count is fixed at 8·len(scalar bytes) / 4 windows, so the
//     scalar's value — including its top bits — cannot change the trace;
//   * the digit selects nothing by address, only by mask (see
//     __p256_tbl_get_d), so there is no secret-dependent load;
//   * digit 0 reads the identity, which the COMPLETE addition formula
//     absorbs correctly — that is what removes the need to special-case
//     it, and with it the last data-dependent branch;
//   * `w` and the nibble position are public loop counters.
//
// The whole ladder runs in storage allocated before it starts — `acc`,
// `added`, the table, the base point and the scratch — so its 334 point
// additions allocate nothing.
@ p256ct_scalarmult ( Vec u ) kbytes ( Vec i ) bx ( Vec i ) by → ( Vec u ) {
    : P256Scratch scr ( __p256_scr_new )
    : ( Vec i ) aplain ( __p256_a_plain )
    : ( Vec i ) am ( __p256_to_mont_s scr aplain )
    ( vec_free [i] aplain )
    : ( Vec i ) b3plain ( __p256_b3_plain )
    : ( Vec i ) b3m ( __p256_to_mont_s scr b3plain )
    ( vec_free [i] b3plain )
    // base in Montgomery projective form (Z = 1).
    : P256Pt base ( __p256_pt_mag )
    ( __p256_to_mont_d scr . base x bx )
    ( __p256_to_mont_d scr . base y by )
    ( __p256_one_mont_d scr . base z )
    : P256Pt acc ( __p256_pt_mag )
    : P256Pt added ( __p256_pt_mag )
    // window table: T[0] = identity, T[d] = T[d-1] + B.
    : ( Vec i ) tbl ( __magn 384 )
    ( __p256_set_identity_d scr acc )
    ( __p256_tbl_put tbl 0 acc )
    ( __p256_tbl_put tbl 1 base )
    ( __p256_pt_copy_d added base )
    : ~ i d 2
    ~ < d 16 {
        ( p256ct_padd_d scr added added base am b3m )
        ( __p256_tbl_put tbl d added )
        = d + d 1
    }
    : i nbytes ( vec_len [u] kbytes )
    // MSB-first nibbles: window 0 is byte 0's high nibble.
    : i nwin * nbytes 2
    : ~ i w 0
    ~ < w nwin {
        ( p256ct_padd_d scr acc acc acc am b3m )
        ( p256ct_padd_d scr acc acc acc am b3m )
        ( p256ct_padd_d scr acc acc acc am b3m )
        ( p256ct_padd_d scr acc acc acc am b3m )
        : i bv ?? ( vec_get [u] kbytes / w 2 ) { T b → # i b F _ → 0 }
        : i digit ? == % w 2 0 & 15 >> bv 4 & 15 bv
        ( __p256_tbl_get_d added tbl digit )
        ( p256ct_padd_d scr acc acc added am b3m )
        = w + w 1
    }
    // affine: x = X/Z, y = Y/Z (de-Montgomery via inverse).
    : ( Vec i ) zinv ( __mag8 )
    ( __p256_inv_d scr zinv . acc z )
    ( __p256_mul_d scr . acc x . acc x zinv )
    ( __p256_mul_d scr . acc y . acc y zinv )
    ( __p256_from_mont_d scr . acc x . acc x )
    ( __p256_from_mont_d scr . acc y . acc y )
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( __p256_limbs_to_be out . acc x )
    ( __p256_limbs_to_be out . acc y )
    ( p256pt_free base ) ( p256pt_free acc ) ( p256pt_free added )
    ( vec_free [i] tbl )
    ( vec_free [i] am ) ( vec_free [i] b3m ) ( vec_free [i] zinv )
    ( __p256_scr_free scr )
    ^ out
}

// Append an 8-limb field element as 32 big-endian bytes to `out`.
@ __p256_limbs_to_be ( Vec u ) out ( Vec i ) v → v {
    : ~ i k 7
    ~ >= k 0 {
        : i lk ( __ctl v k )
        ( vec_push [u] out # u & >> lk 24 255 )
        ( vec_push [u] out # u & >> lk 16 255 )
        ( vec_push [u] out # u & >> lk 8 255 )
        ( vec_push [u] out # u & lk 255 )
        = k - k 1
    }
}
