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
// Elements are STORED as eight 32-bit limbs, but the multiply works in
// four 64-bit ones: it packs its inputs to 4×64 on entry and unpacks the
// result on exit, so each partial product is a full 64×64 → 128 multiply
// (nurl_umulhi gives the high half) and the schoolbook body is 4×4 = 16
// products against the 8×8 = 64 the 32-bit radix ran. Add/sub/conditional-
// subtract stay on the 32-bit limbs, where a 32×32 sum needs no wide type.
// Every limb is stored masked to 32 bits, so reading one back as `u64` is
// exact.
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
    : ( Vec i ) v ( _mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 0xFFFFFFFF = . q 1 0xFFFFFFFF = . q 2 0xFFFFFFFF = . q 3 0
    = . q 4 0 = . q 5 0 = . q 6 1 = . q 7 0xFFFFFFFF
    ^ v
}

// R^2 mod p (= 2^512 mod p) — multiply by this (Montgomery) to enter the domain.
@ __p256_r2 → ( Vec i ) {
    : ( Vec i ) v ( _mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 3 = . q 1 0 = . q 2 0xFFFFFFFF = . q 3 0xFFFFFFFB
    = . q 4 0xFFFFFFFE = . q 5 0xFFFFFFFF = . q 6 0xFFFFFFFD = . q 7 4
    ^ v
}

// 1 in plain (non-Montgomery) form: [1, 0, …]. Montgomery-multiplying by this
// leaves the domain (montmul(ā, 1) = a).
@ __p256_one → ( Vec i ) {
    : ( Vec i ) v ( _mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 1 = . q 1 0 = . q 2 0 = . q 3 0
    = . q 4 0 = . q 5 0 = . q 6 0 = . q 7 0
    ^ v
}

// The Montgomery constant -p^-1 mod 2^32 is 1, because p ≡ −1 (mod 2^32).
// It is not a function any more: _p256_mul_d folds it (and the whole
// modulus) into the reduction as shifts — see there.

@ __ctl ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 } }

// An 8-limb magnitude, uninitialised. The hot routines below fill every
// limb through a raw `*i` before anyone reads one, so there is nothing to
// zero first — and unlike a push loop, filling by index costs no capacity
// check per limb.
@ _mag8 → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 8 )
    : b _l ( vec_set_len [i] v 8 )
    ^ v
}

// The same for an arbitrary limb count (the CIOS accumulator wants 10).
@ _magn i n → ( Vec i ) {
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

@ _p256_scr_new → P256Scratch {
    ^ @ P256Scratch {
        ( __p256_mod ) ( _magn 10 ) ( _mag8 )
        ( _mag8 ) ( _mag8 ) ( _mag8 )
        ( _mag8 ) ( _mag8 ) ( _mag8 )
        ( _mag8 )
    }
}

@ _p256_scr_free P256Scratch s → v {
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
    : ( Vec i ) v ( _mag8 )
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
// same index in the same step. `_p256_inv_d` is the one exception —
// its `dst` must not alias `a`, and its own comment says so.

// Montgomery multiply: returns (a·b·R^-1) mod p as 8 fixed limbs. CIOS, all
// fixed-count loops, no data-dependent branch. a, b are 8-limb (< p).
@ p256ct_mul ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_mul_s scr a b )
    ( _p256_scr_free scr )
    ^ r
}

@ __p256_mul_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( _mag8 )
    ( _p256_mul_d scr out a b )
    ^ out
}

// CIOS Montgomery multiply, radix 2^64. Four 64-bit limbs instead of eight
// 32-bit ones: each a[j]·b[i] is now a full 64×64→128 product (nurl_umulhi
// supplies the high half NURL's `*` drops), so the schoolbook is 16
// products against the 64 the 2^32 radix ran, and the interleaved reduction
// three more per step against seven. The Montgomery constant −p^-1 mod 2^64
// is still 1 — p ≡ −1 (mod 2^64) exactly as it is (mod 2^32) — so m = t[0]
// with no multiply, and the reduction multiplies fold against the sparse
// 4×64 modulus p = [2^64−1, 2^32−1, 0, 2^64−2^32+1].
//
// The 8×32 external limb layout is unchanged: a/b are packed to 4×64 on
// entry and the result unpacked back on exit, so every caller, constant
// table and the whole point/inversion layer are untouched. `dst` may alias
// a or b — both are read into the packed locals before any write to dst.
@ _p256_mul_d P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    // Pack the eight 32-bit limbs into four 64-bit ones (little-endian).
    : u64 a0 | # u64 . ap 0 << # u64 . ap 1 32
    : u64 a1 | # u64 . ap 2 << # u64 . ap 3 32
    : u64 a2 | # u64 . ap 4 << # u64 . ap 5 32
    : u64 a3 | # u64 . ap 6 << # u64 . ap 7 32
    : u64 b0 | # u64 . bp 0 << # u64 . bp 1 32
    : u64 b1 | # u64 . bp 2 << # u64 . bp 3 32
    : u64 b2 | # u64 . bp 4 << # u64 . bp 5 32
    : u64 b3 | # u64 . bp 6 << # u64 . bp 7 32
    // Accumulator t[0..5]; the top two words hold the CIOS overflow.
    : ~ u64 t0 0
    : ~ u64 t1 0
    : ~ u64 t2 0
    : ~ u64 t3 0
    : ~ u64 t4 0
    : ~ u64 t5 0
    : ~ u64 m 0
    : ~ u64 cr 0
    // Every accumulate step is ONE primitive pair: `t[j] + a[j]·bi + carry`
    // is exactly `nurl_mac`, whose `_lo` is the new limb and whose `_hi` is
    // the outgoing carry. Both halves come out of one i128 expression, so
    // the backend emits `mulx` for the product and threads the carry in the
    // flag register — an `adc` chain. The previous shape spelled the same
    // arithmetic as a `*` / `nurl_umulhi` pair plus two hand-written wrap
    // tests (`? < s lo 1 0`), which reads the flags a plain `mul` would
    // clobber and so forced the multiply, the compare, the `setb` and the
    // add to serialise through the ALU, four instructions deep, per limb.
    // Every accumulate step is ONE primitive pair: `t[j] + a[j]·bi + carry`
    // is exactly `nurl_mac`, whose `_lo` is the new limb and whose `_hi` is
    // the outgoing carry. Both halves come out of one i128 expression, so
    // the backend emits a single widening multiply for the product and
    // threads the carry in the flag register as an `adc` chain. The
    // previous shape spelled the same arithmetic as a `*` / `nurl_umulhi`
    // pair plus two hand-written wrap tests (`? < s lo 1 0`), which read
    // the flags a plain `mul` would clobber and so forced the multiply,
    // the compare, the `setb` and the add to serialise through the ALU.
    //
    // The four rounds are written out rather than looped. `b[i]` inside a
    // loop is a chain of three compares and three conditional moves per
    // round — six instructions to re-derive a value that is a constant of
    // the round — and rolled up, the accumulator t0..t5 has to survive
    // the back edge, which pins it to memory. Unrolled, `bi` disappears
    // into the operand of the multiply and the whole accumulator lives in
    // registers from the first product to the last. Measured on this
    // function: 191 instructions rolled, against 137 unrolled, for the
    // same arithmetic.
    // ── round 0: t += a·b0, then one Montgomery reduction ──
    = cr ( nurl_mac_hi a0 b0 t0 0 )
    = t0 ( nurl_mac_lo a0 b0 t0 0 )
    : u64 q01 ( nurl_mac_lo a1 b0 t1 cr )
    = cr ( nurl_mac_hi a1 b0 t1 cr )
    = t1 q01
    : u64 q02 ( nurl_mac_lo a2 b0 t2 cr )
    = cr ( nurl_mac_hi a2 b0 t2 cr )
    = t2 q02
    : u64 q03 ( nurl_mac_lo a3 b0 t3 cr )
    = cr ( nurl_mac_hi a3 b0 t3 cr )
    = t3 q03
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    // m = t0, since −p^-1 ≡ 1 (mod 2^64): no multiply to find it.
    = m t0
    // j=0: the low word of t0 + m·P0 is 0 by construction — that IS
    // the reduction — so only the carry out of it survives.
    = cr ( nurl_mac_hi m 18446744073709551615 t0 0 )
    // j=1: P1 = 2^32−1
    : u64 w01 ( nurl_mac_lo m 4294967295 t1 cr )
    = cr ( nurl_mac_hi m 4294967295 t1 cr )
    = t1 w01
    // j=2: P2 = 0 — no product, just fold the incoming carry.
    : u64 w02 ( nurl_addc_lo t2 cr 0 )
    = cr ( nurl_addc_hi t2 cr 0 )
    = t2 w02
    // j=3: P3 = 2^64−2^32+1
    : u64 w03 ( nurl_mac_lo m 18446744069414584321 t3 cr )
    = cr ( nurl_mac_hi m 18446744069414584321 t3 cr )
    = t3 w03
    // Fold cr into the top words, then divide by 2^64 — the shift
    // down by one limb that gives CIOS its name.
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    = t0 t1 = t1 t2 = t2 t3 = t3 t4 = t4 t5 = t5 0
    // ── round 1: t += a·b1, then one Montgomery reduction ──
    = cr ( nurl_mac_hi a0 b1 t0 0 )
    = t0 ( nurl_mac_lo a0 b1 t0 0 )
    : u64 q11 ( nurl_mac_lo a1 b1 t1 cr )
    = cr ( nurl_mac_hi a1 b1 t1 cr )
    = t1 q11
    : u64 q12 ( nurl_mac_lo a2 b1 t2 cr )
    = cr ( nurl_mac_hi a2 b1 t2 cr )
    = t2 q12
    : u64 q13 ( nurl_mac_lo a3 b1 t3 cr )
    = cr ( nurl_mac_hi a3 b1 t3 cr )
    = t3 q13
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    // m = t0, since −p^-1 ≡ 1 (mod 2^64): no multiply to find it.
    = m t0
    // j=0: the low word of t0 + m·P0 is 0 by construction — that IS
    // the reduction — so only the carry out of it survives.
    = cr ( nurl_mac_hi m 18446744073709551615 t0 0 )
    // j=1: P1 = 2^32−1
    : u64 w11 ( nurl_mac_lo m 4294967295 t1 cr )
    = cr ( nurl_mac_hi m 4294967295 t1 cr )
    = t1 w11
    // j=2: P2 = 0 — no product, just fold the incoming carry.
    : u64 w12 ( nurl_addc_lo t2 cr 0 )
    = cr ( nurl_addc_hi t2 cr 0 )
    = t2 w12
    // j=3: P3 = 2^64−2^32+1
    : u64 w13 ( nurl_mac_lo m 18446744069414584321 t3 cr )
    = cr ( nurl_mac_hi m 18446744069414584321 t3 cr )
    = t3 w13
    // Fold cr into the top words, then divide by 2^64 — the shift
    // down by one limb that gives CIOS its name.
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    = t0 t1 = t1 t2 = t2 t3 = t3 t4 = t4 t5 = t5 0
    // ── round 2: t += a·b2, then one Montgomery reduction ──
    = cr ( nurl_mac_hi a0 b2 t0 0 )
    = t0 ( nurl_mac_lo a0 b2 t0 0 )
    : u64 q21 ( nurl_mac_lo a1 b2 t1 cr )
    = cr ( nurl_mac_hi a1 b2 t1 cr )
    = t1 q21
    : u64 q22 ( nurl_mac_lo a2 b2 t2 cr )
    = cr ( nurl_mac_hi a2 b2 t2 cr )
    = t2 q22
    : u64 q23 ( nurl_mac_lo a3 b2 t3 cr )
    = cr ( nurl_mac_hi a3 b2 t3 cr )
    = t3 q23
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    // m = t0, since −p^-1 ≡ 1 (mod 2^64): no multiply to find it.
    = m t0
    // j=0: the low word of t0 + m·P0 is 0 by construction — that IS
    // the reduction — so only the carry out of it survives.
    = cr ( nurl_mac_hi m 18446744073709551615 t0 0 )
    // j=1: P1 = 2^32−1
    : u64 w21 ( nurl_mac_lo m 4294967295 t1 cr )
    = cr ( nurl_mac_hi m 4294967295 t1 cr )
    = t1 w21
    // j=2: P2 = 0 — no product, just fold the incoming carry.
    : u64 w22 ( nurl_addc_lo t2 cr 0 )
    = cr ( nurl_addc_hi t2 cr 0 )
    = t2 w22
    // j=3: P3 = 2^64−2^32+1
    : u64 w23 ( nurl_mac_lo m 18446744069414584321 t3 cr )
    = cr ( nurl_mac_hi m 18446744069414584321 t3 cr )
    = t3 w23
    // Fold cr into the top words, then divide by 2^64 — the shift
    // down by one limb that gives CIOS its name.
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    = t0 t1 = t1 t2 = t2 t3 = t3 t4 = t4 t5 = t5 0
    // ── round 3: t += a·b3, then one Montgomery reduction ──
    = cr ( nurl_mac_hi a0 b3 t0 0 )
    = t0 ( nurl_mac_lo a0 b3 t0 0 )
    : u64 q31 ( nurl_mac_lo a1 b3 t1 cr )
    = cr ( nurl_mac_hi a1 b3 t1 cr )
    = t1 q31
    : u64 q32 ( nurl_mac_lo a2 b3 t2 cr )
    = cr ( nurl_mac_hi a2 b3 t2 cr )
    = t2 q32
    : u64 q33 ( nurl_mac_lo a3 b3 t3 cr )
    = cr ( nurl_mac_hi a3 b3 t3 cr )
    = t3 q33
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    // m = t0, since −p^-1 ≡ 1 (mod 2^64): no multiply to find it.
    = m t0
    // j=0: the low word of t0 + m·P0 is 0 by construction — that IS
    // the reduction — so only the carry out of it survives.
    = cr ( nurl_mac_hi m 18446744073709551615 t0 0 )
    // j=1: P1 = 2^32−1
    : u64 w31 ( nurl_mac_lo m 4294967295 t1 cr )
    = cr ( nurl_mac_hi m 4294967295 t1 cr )
    = t1 w31
    // j=2: P2 = 0 — no product, just fold the incoming carry.
    : u64 w32 ( nurl_addc_lo t2 cr 0 )
    = cr ( nurl_addc_hi t2 cr 0 )
    = t2 w32
    // j=3: P3 = 2^64−2^32+1
    : u64 w33 ( nurl_mac_lo m 18446744069414584321 t3 cr )
    = cr ( nurl_mac_hi m 18446744069414584321 t3 cr )
    = t3 w33
    // Fold cr into the top words, then divide by 2^64 — the shift
    // down by one limb that gives CIOS its name.
    = t5 ( nurl_addc_lo t5 ( nurl_addc_hi t4 cr 0 ) 0 )
    = t4 ( nurl_addc_lo t4 cr 0 )
    = t0 t1 = t1 t2 = t2 t3 = t3 t4 = t4 t5 = t5 0
    // t0..t3 is the 256-bit result, t4 the extra top word; value < 2p.
    // Conditional subtract p (4×64), then unpack the winner to 8×32 in dst.
    : u64 d0 ( nurl_subb_lo t0 18446744073709551615 0 )
    : ~ u64 bb ( nurl_subb_hi t0 18446744073709551615 0 )
    : u64 d1 ( nurl_subb_lo t1 4294967295 bb )
    = bb ( nurl_subb_hi t1 4294967295 bb )
    : u64 d2 ( nurl_subb_lo t2 0 bb )
    = bb ( nurl_subb_hi t2 0 bb )
    : u64 d3 ( nurl_subb_lo t3 18446744069414584321 bb )
    = bb ( nurl_subb_hi t3 18446744069414584321 bb )
    // top word minus the final borrow: negative ⇒ t < p ⇒ keep t.
    : i topb - # i t4 # i bb
    : u64 mask ? < topb 0 0 18446744073709551615
    : u64 imask ^^ mask 18446744073709551615
    : u64 o0 | & mask d0 & imask t0
    : u64 o1 | & mask d1 & imask t1
    : u64 o2 | & mask d2 & imask t2
    : u64 o3 | & mask d3 & imask t3
    : *i op ( vec_data [i] dst )
    = . op 0 # i & o0 4294967295
    = . op 1 # i & >> o0 32 4294967295
    = . op 2 # i & o1 4294967295
    = . op 3 # i & >> o1 32 4294967295
    = . op 4 # i & o2 4294967295
    = . op 5 # i & >> o2 32 4294967295
    = . op 6 # i & o3 4294967295
    = . op 7 # i & >> o3 32 4294967295
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
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_add_s scr a b )
    ( _p256_scr_free scr )
    ^ r
}

@ __p256_add_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( _mag8 )
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
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_sub_s scr a b )
    ( _p256_scr_free scr )
    ^ r
}

@ __p256_sub_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( _mag8 )
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
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( _p256_to_mont_s scr a )
    ( _p256_scr_free scr )
    ^ r
}

@ _p256_to_mont_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( _mag8 )
    ( _p256_to_mont_d scr out a )
    ^ out
}

@ _p256_to_mont_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    : ( Vec i ) r2 ( __p256_r2 )
    ( _p256_mul_d scr dst a r2 )
    ( vec_free [i] r2 )
}

@ p256ct_from_mont ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_from_mont_s scr a )
    ( _p256_scr_free scr )
    ^ r
}

@ __p256_from_mont_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( _mag8 )
    ( _p256_from_mont_d scr out a )
    ^ out
}

@ _p256_from_mont_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    : ( Vec i ) one ( __p256_one )
    ( _p256_mul_d scr dst a one )
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
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_one_mont_s scr )
    ( _p256_scr_free scr )
    ^ r
}

@ __p256_one_mont_s P256Scratch scr → ( Vec i ) {
    : ( Vec i ) out ( _mag8 )
    ( _p256_one_mont_d scr out )
    ^ out
}

@ _p256_one_mont_d P256Scratch scr ( Vec i ) dst → v {
    : ( Vec i ) one ( __p256_one )
    ( _p256_to_mont_d scr dst one )
    ( vec_free [i] one )
}

// Modular inverse in Montgomery form: a^(p-2) mod p, via a fixed addition
// chain over montmul/montsqr. The exponent p−2 is a public constant, so the
// square/multiply schedule is data-independent. Input/output in Mont form;
// a^(p-2)·R ≡ a^-1·R (mod p). For a == 0 returns 0.
@ p256ct_inv ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_inv_s scr a )
    ( _p256_scr_free scr )
    ^ r
}

@ __p256_inv_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( _mag8 )
    ( _p256_inv_d scr out a )
    ^ out
}

// 256 squarings and 256 multiplies of the Fermat chain, all in place off
// one scratch. UNLIKE the other `_d` workers, `dst` must NOT alias `a`:
// `a` is read on every iteration, and `dst` is the running accumulator.
@ _p256_inv_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    // p-2 = ffffffff00000001000000000000000000000000fffffffffffffffffffffffd
    // Square-and-multiply, MSB→LSB, over the 256-bit exponent's limbs.
    : ( Vec i ) e ( __p256_pm2 )
    : ( Vec i ) prod . scr gp
    ( _p256_one_mont_d scr dst )
    : ~ i bit 255
    ~ >= bit 0 {
        ( _p256_mul_d scr dst dst dst )
        : i li / bit 32
        : i bp % bit 32
        : i b1 & 1 >> ( __ctl e li ) bp
        ( _p256_mul_d scr prod dst a )
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
    : ( Vec i ) v ( _mag8 )
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
@ _p256_pt_mag → P256Pt {
    ^ @ P256Pt { ( _mag8 ) ( _mag8 ) ( _mag8 ) }
}

// a (= −3 mod p) and b3 (= 3·b mod p), plain (non-Montgomery) limbs.
@ _p256_a_plain → ( Vec i ) {
    : ( Vec i ) v ( _mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 0xFFFFFFFC = . q 1 0xFFFFFFFF = . q 2 0xFFFFFFFF = . q 3 0
    = . q 4 0 = . q 5 0 = . q 6 1 = . q 7 0xFFFFFFFF
    ^ v
}

@ _p256_b3_plain → ( Vec i ) {
    : ( Vec i ) v ( _mag8 )
    : *i q ( vec_data [i] v )
    = . q 0 0x777720E2 = . q 1 0xB36AB4BA = . q 2 0x64FB12E2 = . q 3 0x2F571411
    = . q 4 0x63C99435 = . q 5 0x1BC33800 = . q 6 0xFEAFBBB6 = . q 7 0x1052A18A
    ^ v
}

// Complete projective point addition, RCB Algorithm 4 (a = −3). All operands
// in Montgomery form; `am` = a, `b3m` = b3 in Montgomery form.
@ p256ct_padd P256Scratch scr P256Pt P P256Pt Q ( Vec i ) am ( Vec i ) b3m → P256Pt {
    : P256Pt out ( _p256_pt_mag )
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
    ( _p256_mul_d scr t0 X1 X2 )  //  1
    ( _p256_mul_d scr t1 Y1 Y2 )  //  2
    ( _p256_mul_d scr t2 Z1 Z2 )  //  3
    ( __p256_add_d scr t3 X1 Y1 )  //  4
    ( __p256_add_d scr t4 X2 Y2 )  //  5
    ( _p256_mul_d scr t3 t3 t4 )  //  6
    ( __p256_add_d scr t4 t0 t1 )  //  7
    ( __p256_sub_d scr t3 t3 t4 )  //  8
    ( __p256_add_d scr t4 X1 Z1 )  //  9
    ( __p256_add_d scr t5 X2 Z2 )  // 10
    ( _p256_mul_d scr t4 t4 t5 )  // 11
    ( __p256_add_d scr t5 t0 t2 )  // 12
    ( __p256_sub_d scr t4 t4 t5 )  // 13
    ( __p256_add_d scr t5 Y1 Z1 )  // 14
    ( __p256_add_d scr X3 Y2 Z2 )  // 15
    ( _p256_mul_d scr t5 t5 X3 )  // 16
    ( __p256_add_d scr X3 t1 t2 )  // 17
    ( __p256_sub_d scr t5 t5 X3 )  // 18
    ( _p256_mul_d scr Z3 am t4 )  // 19
    ( _p256_mul_d scr X3 b3m t2 )  // 20
    ( __p256_add_d scr Z3 X3 Z3 )  // 21
    ( __p256_sub_d scr X3 t1 Z3 )  // 22
    ( __p256_add_d scr Z3 t1 Z3 )  // 23
    ( _p256_mul_d scr Y3 X3 Z3 )  // 24
    ( __p256_add_d scr t1 t0 t0 )  // 25
    ( __p256_add_d scr t1 t1 t0 )  // 26
    ( _p256_mul_d scr t2 am t2 )  // 27
    ( _p256_mul_d scr t4 b3m t4 )  // 28
    ( __p256_add_d scr t1 t1 t2 )  // 29
    ( __p256_sub_d scr t2 t0 t2 )  // 30
    ( _p256_mul_d scr t2 am t2 )  // 31
    ( __p256_add_d scr t4 t4 t2 )  // 32
    ( _p256_mul_d scr t0 t1 t4 )  // 33
    ( __p256_add_d scr Y3 Y3 t0 )  // 34
    ( _p256_mul_d scr t0 t5 t4 )  // 35
    ( _p256_mul_d scr X3 t3 X3 )  // 36
    ( __p256_sub_d scr X3 X3 t0 )  // 37
    ( _p256_mul_d scr t0 t3 t1 )  // 38
    ( _p256_mul_d scr Z3 t5 Z3 )  // 39
    ( __p256_add_d scr Z3 Z3 t0 )  // 40
}

// Constant-time select between two points (each coordinate via masked merge).
@ p256ct_pt_select i bit P256Pt a P256Pt b → P256Pt {
    : P256Pt out ( _p256_pt_mag )
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
    : ( Vec i ) out ( _mag8 )
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
@ _p256_set_identity_d P256Scratch scr P256Pt dst → v {
    : *i xp ( vec_data [i] . dst x )
    : *i zp ( vec_data [i] . dst z )
    : ~ i k 0
    ~ < k 8 { = . xp k 0 = . zp k 0 = k + k 1 }
    ( _p256_one_mont_d scr . dst y )
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

@ _p256_tbl_put ( Vec i ) tbl i d P256Pt p → v {
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
@ _p256_tbl_get_d P256Pt dst ( Vec i ) tbl i digit → v {
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
//     _p256_tbl_get_d), so there is no secret-dependent load;
//   * digit 0 reads the identity, which the COMPLETE addition formula
//     absorbs correctly — that is what removes the need to special-case
//     it, and with it the last data-dependent branch;
//   * `w` and the nibble position are public loop counters.
//
// The whole ladder runs in storage allocated before it starts — `acc`,
// `added`, the table, the base point and the scratch — so its 334 point
// additions allocate nothing.
@ p256ct_scalarmult ( Vec u ) kbytes ( Vec i ) bx ( Vec i ) by → ( Vec u ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) aplain ( _p256_a_plain )
    : ( Vec i ) am ( _p256_to_mont_s scr aplain )
    ( vec_free [i] aplain )
    : ( Vec i ) b3plain ( _p256_b3_plain )
    : ( Vec i ) b3m ( _p256_to_mont_s scr b3plain )
    ( vec_free [i] b3plain )
    // base in Montgomery projective form (Z = 1).
    : P256Pt base ( _p256_pt_mag )
    ( _p256_to_mont_d scr . base x bx )
    ( _p256_to_mont_d scr . base y by )
    ( _p256_one_mont_d scr . base z )
    : P256Pt acc ( _p256_pt_mag )
    : P256Pt added ( _p256_pt_mag )
    // window table: T[0] = identity, T[d] = T[d-1] + B.
    : ( Vec i ) tbl ( _magn 384 )
    ( _p256_set_identity_d scr acc )
    ( _p256_tbl_put tbl 0 acc )
    ( _p256_tbl_put tbl 1 base )
    ( __p256_pt_copy_d added base )
    : ~ i d 2
    ~ < d 16 {
        ( p256ct_padd_d scr added added base am b3m )
        ( _p256_tbl_put tbl d added )
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
        ( _p256_tbl_get_d added tbl digit )
        ( p256ct_padd_d scr acc acc added am b3m )
        = w + w 1
    }
    // affine: x = X/Z, y = Y/Z (de-Montgomery via inverse).
    : ( Vec i ) zinv ( _mag8 )
    ( _p256_inv_d scr zinv . acc z )
    ( _p256_mul_d scr . acc x . acc x zinv )
    ( _p256_mul_d scr . acc y . acc y zinv )
    ( _p256_from_mont_d scr . acc x . acc x )
    ( _p256_from_mont_d scr . acc y . acc y )
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( _p256_limbs_to_be out . acc x )
    ( _p256_limbs_to_be out . acc y )
    ( p256pt_free base ) ( p256pt_free acc ) ( p256pt_free added )
    ( vec_free [i] tbl )
    ( vec_free [i] am ) ( vec_free [i] b3m ) ( vec_free [i] zinv )
    ( _p256_scr_free scr )
    ^ out
}

// Append an 8-limb field element as 32 big-endian bytes to `out`.
@ _p256_limbs_to_be ( Vec u ) out ( Vec i ) v → v {
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
