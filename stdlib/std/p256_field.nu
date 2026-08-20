// stdlib/std/p256_field.nu — constant-time GF(p) arithmetic for NIST P-256.
//
// A dedicated FIXED-WIDTH field: every element is exactly 4 little-endian
// 64-bit limbs (256 bits, stored as i64 bit patterns), NEVER normalized/
// trimmed, so no operation's duration depends on the value. This is the
// constant-time core the generic std/bigint.nu cannot be (it trims
// leading-zero limbs → operand-time-dependent). Multiplication is
// Montgomery CIOS; add/sub use a constant-time conditional ±p; inversion
// is a fixed Fermat chain (a^(p-2)). All loops are fixed-count and
// branch-free in the data.
//
// Storage USED to be eight 32-bit limbs with the multiply packing to
// 4×64 on entry and unpacking on exit — ~24 pack/unpack operations
// riding along on EVERY field multiply, i.e. on each of the ~1500
// multiplies of one scalar multiplication. With nurl_addc/nurl_subb
// carrying 64-bit adds and subtracts directly, the 4×64 form is now the
// storage form and the packing is gone.
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

// p = 2^256 − 2^224 + 2^192 + 2^96 − 1, little-endian 64-bit limbs.
@ __p256_mod → ( Vec i ) {
    // Filled by index, not pushed: a push carries a capacity check the
    // fixed four limbs do not need.
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0xFFFFFFFFFFFFFFFF = . q 1 # i 0x00000000FFFFFFFF
    = . q 2 0 = . q 3 # i 0xFFFFFFFF00000001
    ^ v
}

// R^2 mod p (= 2^512 mod p) — multiply by this (Montgomery) to enter the domain.
@ __p256_r2 → ( Vec i ) {
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 3 = . q 1 # i 0xFFFFFFFBFFFFFFFF
    = . q 2 # i 0xFFFFFFFFFFFFFFFE = . q 3 # i 0x00000004FFFFFFFD
    ^ v
}

// 1 in plain (non-Montgomery) form: [1, 0, …]. Montgomery-multiplying by this
// leaves the domain (montmul(ā, 1) = a).
@ __p256_one → ( Vec i ) {
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 1 = . q 1 0 = . q 2 0 = . q 3 0
    ^ v
}

// The Montgomery constant -p^-1 mod 2^32 is 1, because p ≡ −1 (mod 2^32).
// It is not a function any more: _p256_mul_d folds it (and the whole
// modulus) into the reduction as shifts — see there.

@ __ctl ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 } }

// A 4-limb magnitude, uninitialised. The hot routines below fill every
// limb through a raw `*i` before anyone reads one, so there is nothing to
// zero first — and unlike a push loop, filling by index costs no capacity
// check per limb.
@ _mag4 → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 4 )
    : b _l ( vec_set_len [i] v 4 )
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
        ( __p256_mod ) ( _mag4 ) ( _mag4 )
        ( _mag4 ) ( _mag4 ) ( _mag4 )
        ( _mag4 ) ( _mag4 ) ( _mag4 )
        ( _mag4 )
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

@ __zeros4 → ( Vec i ) {
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 0 = . q 1 0 = . q 2 0 = . q 3 0
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
    : ( Vec i ) out ( _mag4 )
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
    // Limbs load directly — the field IS 4×64 now (no pack step).
    : u64 a0 # u64 . ap 0
    : u64 a1 # u64 . ap 1
    : u64 a2 # u64 . ap 2
    : u64 a3 # u64 . ap 3
    : u64 b0 # u64 . bp 0
    : u64 b1 # u64 . bp 1
    : u64 b2 # u64 . bp 2
    : u64 b3 # u64 . bp 3
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
    // Conditional subtract p (4×64); the winner IS the stored form.
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
    = . op 0 # i o0
    = . op 1 # i o1
    = . op 2 # i o2
    = . op 3 # i o3
}

// (kept: the 9-limb staging cond-sub is gone — add/sub carry in
// registers now and fold the conditional ±p inline, like the multiply.)

// (a + b) mod p, constant-time. a, b < p ⇒ a+b < 2p ⇒ one conditional sub.
@ p256ct_add ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_add_s scr a b )
    ( _p256_scr_free scr )
    ^ r
}

@ __p256_add_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
    ( __p256_add_d scr out a b )
    ^ out
}

// (a + b) then one constant-time conditional subtract of p, all in
// registers: a, b < p ⇒ a+b < 2p ⇒ one masked subtract suffices. `dst`
// may alias a and/or b — everything is read before dst is written.
@ __p256_add_d P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : u64 a0 # u64 . ap 0
    : u64 a1 # u64 . ap 1
    : u64 a2 # u64 . ap 2
    : u64 a3 # u64 . ap 3
    : u64 b0 # u64 . bp 0
    : u64 b1 # u64 . bp 1
    : u64 b2 # u64 . bp 2
    : u64 b3 # u64 . bp 3
    : u64 t0 ( nurl_addc_lo a0 b0 0 )
    : ~ u64 cc ( nurl_addc_hi a0 b0 0 )
    : u64 t1 ( nurl_addc_lo a1 b1 cc )
    = cc ( nurl_addc_hi a1 b1 cc )
    : u64 t2 ( nurl_addc_lo a2 b2 cc )
    = cc ( nurl_addc_hi a2 b2 cc )
    : u64 t3 ( nurl_addc_lo a3 b3 cc )
    = cc ( nurl_addc_hi a3 b3 cc )
    // conditional subtract p, exactly the multiply's tail.
    : u64 d0 ( nurl_subb_lo t0 18446744073709551615 0 )
    : ~ u64 bb ( nurl_subb_hi t0 18446744073709551615 0 )
    : u64 d1 ( nurl_subb_lo t1 4294967295 bb )
    = bb ( nurl_subb_hi t1 4294967295 bb )
    : u64 d2 ( nurl_subb_lo t2 0 bb )
    = bb ( nurl_subb_hi t2 0 bb )
    : u64 d3 ( nurl_subb_lo t3 18446744069414584321 bb )
    = bb ( nurl_subb_hi t3 18446744069414584321 bb )
    : i topb - # i cc # i bb
    : u64 mask ? < topb 0 0 18446744073709551615
    : u64 imask ^^ mask 18446744073709551615
    : *i op ( vec_data [i] dst )
    = . op 0 # i | & mask d0 & imask t0
    = . op 1 # i | & mask d1 & imask t1
    = . op 2 # i | & mask d2 & imask t2
    = . op 3 # i | & mask d3 & imask t3
}

// (a − b) mod p, constant-time: a − b, and if it borrows add p back.
@ p256ct_sub ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_sub_s scr a b )
    ( _p256_scr_free scr )
    ^ r
}

@ __p256_sub_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
    ( __p256_sub_d scr out a b )
    ^ out
}

// a − b with borrow, then a masked add-back of p when it underflowed.
// `dst` may alias a and/or b.
@ __p256_sub_d P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : u64 a0 # u64 . ap 0
    : u64 a1 # u64 . ap 1
    : u64 a2 # u64 . ap 2
    : u64 a3 # u64 . ap 3
    : u64 b0 # u64 . bp 0
    : u64 b1 # u64 . bp 1
    : u64 b2 # u64 . bp 2
    : u64 b3 # u64 . bp 3
    : u64 d0 ( nurl_subb_lo a0 b0 0 )
    : ~ u64 bb ( nurl_subb_hi a0 b0 0 )
    : u64 d1 ( nurl_subb_lo a1 b1 bb )
    = bb ( nurl_subb_hi a1 b1 bb )
    : u64 d2 ( nurl_subb_lo a2 b2 bb )
    = bb ( nurl_subb_hi a2 b2 bb )
    : u64 d3 ( nurl_subb_lo a3 b3 bb )
    = bb ( nurl_subb_hi a3 b3 bb )
    // if it borrowed (a < b), add p back — masked, no branch.
    : u64 mask ? == # i bb 0 0 18446744073709551615
    : u64 p0 & mask 18446744073709551615
    : u64 p1 & mask 4294967295
    : u64 p3 & mask 18446744069414584321
    : u64 r0 ( nurl_addc_lo d0 p0 0 )
    : ~ u64 cc ( nurl_addc_hi d0 p0 0 )
    : u64 r1 ( nurl_addc_lo d1 p1 cc )
    = cc ( nurl_addc_hi d1 p1 cc )
    : u64 r2 ( nurl_addc_lo d2 0 cc )
    = cc ( nurl_addc_hi d2 0 cc )
    : u64 r3 ( nurl_addc_lo d3 p3 cc )
    : *i op ( vec_data [i] dst )
    = . op 0 # i r0
    = . op 1 # i r1
    = . op 2 # i r2
    = . op 3 # i r3
}

@ p256ct_sqr ( Vec i ) a → ( Vec i ) { ^ ( p256ct_mul a a ) }

@ p256ct_to_mont ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( _p256_to_mont_s scr a )
    ( _p256_scr_free scr )
    ^ r
}

@ _p256_to_mont_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
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
    : ( Vec i ) out ( _mag4 )
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
    ~ < k 4 { = acc | acc ( __ctl a k ) = k + k 1 }
    ^ == acc 0
}

// Montgomery 1 (= R mod p), the field identity in Montgomery form.
@ p256ct_one_mont → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( _p256_one_mont_s scr )
    ( _p256_scr_free scr )
    ^ r
}

@ _p256_one_mont_s P256Scratch scr → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
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
    : ( Vec i ) out ( _mag4 )
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
        : i li / bit 64
        : i bp % bit 64
        : i b1 & 1 # i >> # u64 ( __ctl e li ) bp
        ( _p256_mul_d scr prod dst a )
        // constant-time select prod (if bit) else the running value
        : i mask - 0 b1
        : i imask - 0 - 1 b1
        ( __p256_lmerge_d dst mask imask prod dst )
        = bit - bit 1
    }
    ( vec_free [i] e )
}

// p − 2, little-endian 64-bit limbs.
@ __p256_pm2 → ( Vec i ) {
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0xFFFFFFFFFFFFFFFD = . q 1 # i 0x00000000FFFFFFFF
    = . q 2 0 = . q 3 # i 0xFFFFFFFF00000001
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
    ^ @ P256Pt { ( _mag4 ) ( _mag4 ) ( _mag4 ) }
}

// a (= −3 mod p) and b3 (= 3·b mod p), plain (non-Montgomery) limbs.
@ _p256_a_plain → ( Vec i ) {
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0xFFFFFFFFFFFFFFFC = . q 1 # i 0x00000000FFFFFFFF
    = . q 2 0 = . q 3 # i 0xFFFFFFFF00000001
    ^ v
}

@ _p256_b3_plain → ( Vec i ) {
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0xB36AB4BA777720E2 = . q 1 # i 0x2F57141164FB12E2
    = . q 2 # i 0x1BC3380063C99435 = . q 3 # i 0x1052A18AFEAFBBB6
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
    : i mask - 0 bit
    : i imask - 0 - 1 bit
    ( __p256_lmerge_d . dst x mask imask . a x . b x )
    ( __p256_lmerge_d . dst y mask imask . a y . b y )
    ( __p256_lmerge_d . dst z mask imask . a z . b z )
}

@ __p256_lmerge_d ( Vec i ) dst i mask i imask ( Vec i ) a ( Vec i ) b → v {
    : *i op ( vec_data [i] dst )
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    = . op 0 | & mask . ap 0 & imask . bp 0
    = . op 1 | & mask . ap 1 & imask . bp 1
    = . op 2 | & mask . ap 2 & imask . bp 2
    = . op 3 | & mask . ap 3 & imask . bp 3
}

@ p256ct_pt_clone P256Pt p → P256Pt {
    ^ @ P256Pt { ( __mag4_clone . p x ) ( __mag4_clone . p y ) ( __mag4_clone . p z ) }
}

@ __mag4_clone ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
    ( __p256_copy_d out a )
    ^ out
}

@ __p256_copy_d ( Vec i ) dst ( Vec i ) a → v {
    : *i op ( vec_data [i] dst )
    : *i ap ( vec_data [i] a )
    = . op 0 . ap 0
    = . op 1 . ap 1
    = . op 2 . ap 2
    = . op 3 . ap 3
}

// Identity point (0 : 1 : 0) in Montgomery form.
@ p256ct_identity → P256Pt {
    : ( Vec i ) z0 ( __zeros4 )
    : ( Vec i ) one ( p256ct_one_mont )
    : ( Vec i ) z0b ( __zeros4 )
    ^ @ P256Pt { z0 one z0b }
}

// Set an existing point to the identity, off the caller's scratch.
@ _p256_set_identity_d P256Scratch scr P256Pt dst → v {
    : *i xp ( vec_data [i] . dst x )
    : *i zp ( vec_data [i] . dst z )
    = . xp 0 0 = . xp 1 0 = . xp 2 0 = . xp 3 0
    = . zp 0 0 = . zp 1 0 = . zp 2 0 = . zp 3 0
    ( _p256_one_mont_d scr . dst y )
}

@ __p256_pt_copy_d P256Pt dst P256Pt a → v {
    ( __p256_copy_d . dst x . a x )
    ( __p256_copy_d . dst y . a y )
    ( __p256_copy_d . dst z . a z )
}

// ── Jacobian fixed-base machinery ──────────────────────────────────────
// The FIXED-BASE comb (k·G: ECDSA nonce, ECDH keygen) runs on Jacobian
// coordinates (x = X/Z², y = Y/Z³, ∞ ⇔ Z = 0) with an AFFINE table of
// G-multiples: doubling is 3M+5S (dbl-2001-b, a = −3) and mixed addition
// 8M+3S, against the complete projective formula's 14 multiplies for
// BOTH. The completeness the RCB formula buys is replaced case by case:
//
//   * acc = ∞  (leading zero teeth): the mixed add's result is fixed up
//     by a constant-time select of (x2, y2, 1) — Z1 = 0 is detected with
//     a branch-free mask, and the doubling formula keeps Z = 0 on its
//     own (Z3 = (Y+Z)² − Y² − Z² = 0 when Z = 0).
//   * digit = 0 (no affine entry exists for ∞): the caller keeps the
//     old accumulator through the same masked select — the add still
//     RUNS, against the table's zero entry, so the trace is identical.
//   * acc = −entry: H = 0, R ≠ 0 → Z3 = Z1·H = 0 — the formula itself
//     yields ∞, which is the right answer.
//   * acc = entry (the doubling case, H = 0, R = 0): the formula
//     degenerates. For this to trigger, the partial sum (a multiple of
//     G determined by the scalar's higher teeth) must equal the table
//     entry's multiple mod n — for the secret, (pseudo)random scalars
//     this path serves (RFC 6979 nonces, ephemeral ECDH keys) that is a
//     ~2⁻²²⁴ event per addition, the same bound production
//     implementations (e.g. ecp_nistz256) accept. Adversarial scalars
//     never reach this path: the VARIABLE-base ladder keeps the
//     complete formula.
//
// All limb traffic stays masked and fixed-count: same constant-time
// discipline as the projective path.

// Jacobian doubling in place, a = −3 (dbl-2001-b): 3M+5S.
// Registers: g0=delta g1=gamma g2=beta g3=alpha g4/g5=temps.
@ _p256_jdbl_d P256Scratch scr P256Pt pt → v {
    : ( Vec i ) xr . pt x
    : ( Vec i ) yr . pt y
    : ( Vec i ) zr . pt z
    : ( Vec i ) delta . scr g0
    : ( Vec i ) gamma . scr g1
    : ( Vec i ) beta . scr g2
    : ( Vec i ) alpha . scr g3
    : ( Vec i ) t4 . scr g4
    : ( Vec i ) t5 . scr g5
    ( _p256_mul_d scr delta zr zr )
    ( _p256_mul_d scr gamma yr yr )
    ( _p256_mul_d scr beta xr gamma )
    // alpha = 3·(xr − delta)·(xr + delta)
    ( __p256_sub_d scr t4 xr delta )
    ( __p256_add_d scr t5 xr delta )
    ( _p256_mul_d scr alpha t4 t5 )
    ( __p256_add_d scr t4 alpha alpha )
    ( __p256_add_d scr alpha t4 alpha )
    // Z3 = (yr + zr)² − gamma − delta   (before xr/yr are overwritten)
    ( __p256_add_d scr t4 yr zr )
    ( _p256_mul_d scr t4 t4 t4 )
    ( __p256_sub_d scr t4 t4 gamma )
    ( __p256_sub_d scr zr t4 delta )
    // X3 = alpha² − 8·beta
    ( _p256_mul_d scr t4 alpha alpha )
    ( __p256_add_d scr t5 beta beta )
    ( __p256_add_d scr t5 t5 t5 )
    ( __p256_add_d scr delta t5 t5 )
    ( __p256_sub_d scr xr t4 delta )
    // Y3 = alpha·(4·beta − X3) − 8·gamma²
    ( __p256_sub_d scr t4 t5 xr )
    ( _p256_mul_d scr t4 alpha t4 )
    ( _p256_mul_d scr t5 gamma gamma )
    ( __p256_add_d scr t5 t5 t5 )
    ( __p256_add_d scr t5 t5 t5 )
    ( __p256_add_d scr t5 t5 t5 )
    ( __p256_sub_d scr yr t4 t5 )
}

// Branch-free "all four limbs zero" mask: −1 when v == 0, else 0.
@ __p256_zmask ( Vec i ) v → i {
    : *i vp ( vec_data [i] v )
    : i zz | | | . vp 0 . vp 1 | . vp 2 . vp 3 0
    // (zz | −zz) has its top bit set exactly when zz ≠ 0.
    : i nz # i >> # u64 | zz - 0 zz 63
    ^ - 0 - 1 nz
}

// Mixed Jacobian += affine (x2, y2), with the masked fixups the header
// describes. `keep` is a FULL-WIDTH mask (−1 keeps the old accumulator —
// the digit-0 case; 0 commits normally); acc = ∞ is detected here and
// commits (x2, y2, 1) instead. `one_m` is the Montgomery 1, owned by the
// caller. The accumulator is NOT touched until the masked commit at the
// end, so both fixup paths still see the old point. Uses every scratch
// register (g0..g5 + gp).
@ _p256_jmadd_d P256Scratch scr P256Pt acc ( Vec i ) x2 ( Vec i ) y2 ( Vec i ) one_m i keep → v {
    : ( Vec i ) X1 . acc x
    : ( Vec i ) Y1 . acc y
    : ( Vec i ) Z1 . acc z
    : ( Vec i ) z3 . scr g0
    : ( Vec i ) hreg . scr g1
    : ( Vec i ) rreg . scr g2
    : ( Vec i ) hh . scr g3
    : ( Vec i ) x3 . scr g4
    : ( Vec i ) vv . scr g5
    : ( Vec i ) t . scr gp
    : i inf_mask ( __p256_zmask Z1 )
    // zz = Z1²; u2 = x2·zz; s2 = y2·Z1·zz
    ( _p256_mul_d scr z3 Z1 Z1 )
    ( _p256_mul_d scr hreg x2 z3 )
    ( _p256_mul_d scr t z3 Z1 )
    ( _p256_mul_d scr rreg y2 t )
    // H = u2 − X1; R = s2 − Y1
    ( __p256_sub_d scr hreg hreg X1 )
    ( __p256_sub_d scr rreg rreg Y1 )
    // Z3 = Z1·H (into its own register — acc stays whole until commit)
    ( _p256_mul_d scr z3 Z1 hreg )
    // hh = H²; V = X1·hh; X3 = R² − H³ − 2V
    ( _p256_mul_d scr hh hreg hreg )
    ( _p256_mul_d scr vv X1 hh )
    ( _p256_mul_d scr x3 rreg rreg )
    ( _p256_mul_d scr hh hreg hh )
    ( __p256_sub_d scr x3 x3 hh )
    ( __p256_sub_d scr x3 x3 vv )
    ( __p256_sub_d scr x3 x3 vv )
    // Y3 = R·(V − X3) − Y1·H³
    ( __p256_sub_d scr vv vv x3 )
    ( _p256_mul_d scr vv rreg vv )
    ( _p256_mul_d scr t Y1 hh )
    ( __p256_sub_d scr vv vv t )
    // Masked two-stage commit: result ← (∞ ? affine : computed), then
    // acc ← (keep ? acc : result). Element-wise merges, no branches.
    : i ninf ^^ inf_mask - 0 1
    : i nkeep ^^ keep - 0 1
    ( __p256_lmerge_d x3 inf_mask ninf x2 x3 )
    ( __p256_lmerge_d vv inf_mask ninf y2 vv )
    ( __p256_lmerge_d z3 inf_mask ninf one_m z3 )
    ( __p256_lmerge_d X1 nkeep keep x3 X1 )
    ( __p256_lmerge_d Y1 nkeep keep vv Y1 )
    ( __p256_lmerge_d Z1 nkeep keep z3 Z1 )
}

// ── affine window table (fixed-base comb) ─────────────────────────────
// Affine Montgomery multiples of G: entry d occupies [d·8, d·8+8) as
// x‖y. Entry 0 is all-zero — the comb never COMMITS it (digit 0 keeps
// the accumulator via _p256_jmadd_d's mask), but the scan still reads
// it so the trace is digit-independent.

@ _p256_atbl_put ( Vec i ) tbl i d ( Vec i ) ax ( Vec i ) ay → v {
    : *i tp ( vec_data [i] tbl )
    : *i xp ( vec_data [i] ax )
    : *i yp ( vec_data [i] ay )
    : i base * d 8
    = . tp + base 0 . xp 0
    = . tp + base 1 . xp 1
    = . tp + base 2 . xp 2
    = . tp + base 3 . xp 3
    = . tp + base 4 . yp 0
    = . tp + base 5 . yp 1
    = . tp + base 6 . yp 2
    = . tp + base 7 . yp 3
}

// Constant-time masked read of entry `digit` into (ex, ey): reads all
// sixteen entries, merges under an arithmetic equality mask — same
// discipline as _p256_tbl_get_d.
@ _p256_atbl_get_d ( Vec i ) ex ( Vec i ) ey ( Vec i ) tbl i digit → v {
    : *i tp ( vec_data [i] tbl )
    : *i xp ( vec_data [i] ex )
    : *i yp ( vec_data [i] ey )
    = . xp 0 0 = . xp 1 0 = . xp 2 0 = . xp 3 0
    = . yp 0 0 = . yp 1 0 = . yp 2 0 = . yp 3 0
    : ~ i d 0
    ~ < d 16 {
        : u64 z ^^ # u64 d # u64 digit
        : i mask - 0 # i >> - z 1 63
        : i base * d 8
        : ~ i j 0
        ~ < j 4 {
            = . xp j | . xp j & mask . tp + base j
            = . yp j | . yp j & mask . tp + + base 4 j
            = j + j 1
        }
        = d + d 1
    }
}

// ── the window table ──────────────────────────────────────────────────
// Sixteen projective multiples of the base point, 0·B … 15·B, in one flat
// limb vector: entry d occupies [d·12, d·12+12) as x‖y‖z. Flat because the
// constant-time read below has to walk EVERY entry, and a straight run of
// limbs is what that walk wants.

@ _p256_tbl_put ( Vec i ) tbl i d P256Pt p → v {
    : *i tp ( vec_data [i] tbl )
    : *i xp ( vec_data [i] . p x )
    : *i yp ( vec_data [i] . p y )
    : *i zp ( vec_data [i] . p z )
    : i base * d 12
    : ~ i k 0
    ~ < k 4 {
        = . tp + base k . xp k
        = . tp + + base 4 k . yp k
        = . tp + + base 8 k . zp k
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
    = . xp 0 0 = . xp 1 0 = . xp 2 0 = . xp 3 0
    = . yp 0 0 = . yp 1 0 = . yp 2 0 = . yp 3 0
    = . zp 0 0 = . zp 1 0 = . zp 2 0 = . zp 3 0
    : ~ i d 0
    ~ < d 16 {
        : u64 z ^^ # u64 d # u64 digit
        : i mask - 0 # i >> - z 1 63
        : i base * d 12
        : ~ i j 0
        ~ < j 4 {
            = . xp j | . xp j & mask . tp + base j
            = . yp j | . yp j & mask . tp + + base 4 j
            = . zp j | . zp j & mask . tp + + base 8 j
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
    : ( Vec i ) tbl ( _magn 192 )
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
    : ( Vec i ) zinv ( _mag4 )
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

// Append a 4-limb field element as 32 big-endian bytes to `out`.
@ _p256_limbs_to_be ( Vec u ) out ( Vec i ) v → v {
    : ~ i k 3
    ~ >= k 0 {
        : u64 lk # u64 ( __ctl v k )
        : ~ i sh 56
        ~ >= sh 0 {
            ( vec_push [u] out # u & # i >> lk sh 255 )
            = sh - sh 8
        }
        = k - k 1
    }
}
