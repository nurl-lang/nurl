// stdlib/std/p256_field.nu — constant-time GF(p) arithmetic for NIST P-256.
//
// A dedicated FIXED-WIDTH field: every element is exactly 4 little-endian
// 64-bit limbs (256 bits, stored as i64 bit patterns), NEVER normalized/
// trimmed, so no operation's duration depends on the value. This is the
// constant-time core the generic std/bigint.nu cannot be (it trims
// leading-zero limbs → operand-time-dependent). Multiplication is
// Montgomery CIOS; add/sub use a constant-time conditional ±p; inversion
// is std/modinv's fixed walk of divsteps. All loops are fixed-count and
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
// Both forms of every operation that takes an element are `raw` (spec
// §3.3e): each requires its operands to hold four limbs — and a point's
// coordinates, a scratch's registers, a table's slots the sizes its
// comment names — and reads and writes them through `vec_data` with no
// length check; a check per field operation would cost a scalar multiply
// more than the operation. P256Pt and P256Scratch are sealed (`raw :`) for
// the same reason. Their callers here and in std/ecdsa_p256 build every
// element themselves; a program calls the byte-level surface
// (p256ct_scalarmult_base, p256ct_scalarmult, std/ecdsa_p256), which
// checks sizes once.
//
// Elements live in Montgomery form (ā = a·R mod p, R = 2^256) so that
// p256ct_mul ā b̄ = (a·b)·R mod p stays in form. Convert in with
// p256ct_to_mont, out with p256ct_from_mont. Used by the secret-scalar P-256
// point multiply (ECDSA nonce / ECDH); verify keeps the public bigint path.

$ `stdlib/core/vec.nu`
$ `stdlib/std/modinv.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/p256_scalar.nu`  // reduction mod n before either scalar multiply

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
// requires: the caller writes all four limbs before any is read (they
// start uninitialised).
raw @ _mag4 → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 4 )
    : b _l ( vec_set_len [i] v 4 )
    ^ v
}

// The same for an arbitrary limb count (the CIOS accumulator wants 10).
// requires: the caller writes all n limbs before any is read (they start
// uninitialised).
raw @ _magn i n → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : b _l ( vec_set_len [i] v n )
    ^ v
}

// ── field scratch ─────────────────────────────────────────────────────
// Every temporary a scalar multiply needs, allocated once and held for the
// whole ladder: the modulus, the CIOS accumulator and difference, the six
// registers RCB point addition works in, and one spare (gp) for the point
// formulas.
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
// owns t/diff, the mixed addition owns gp).
raw : P256Scratch {
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
// same index in the same step.

// Montgomery multiply: returns (a·b·R^-1) mod p as 8 fixed limbs. CIOS, all
// fixed-count loops, no data-dependent branch. a, b are 8-limb (< p).
// requires: a and b hold 4 limbs.
raw @ p256ct_mul ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_mul_s scr a b )
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
// The multiply and the square on limb pointers: the register kernel where
// the target has one, the portable form elsewhere. The point formulas
// take their operands' data pointers once and run on these, rather than
// re-deriving each Vec's data pointer around every operation.
inline @ __p256_mul_p * i op * i ap * i bp → v { ? ( nurl_p256_mulm op ap bp ) {} { ( __p256_mul_port_p op ap bp ) } }

inline @ __p256_sqr_p * i op * i ap → v { ? ( nurl_p256_sqrm op ap ) {} { ( __p256_sqr_port_p op ap ) } }

// The field kernel P-256's scalar multiplies run on this CPU, by name:
// `adx` (mulx with adcx/adox), `mulq` (x86-64 without ADX) or `portable`
// (the CIOS below: a target with no kernel). The kernel answers for
// itself — a multiply of zeros says whether a block ran it — and
// NURL_CPU_ADX=0 masks `adx`. For reports and diagnostics.
@ p256_cpu_tier → s {
    : ( Vec i ) z ( __zeros4 )
    : *i zp ( vec_data [i] z )
    ? ! ( nurl_p256_mulm zp zp zp ) { ^ `portable` } {}
    ^ ? ( nurl_cpu_has_adx ) `adx` `mulq`
}

// requires: every field-element operand (dst included) holds 4 limbs.
raw @ _p256_mul_d P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v {
    // The register kernel where the target has one (x86-64: the ADX tier
    // or mulq — the compiler's nurl_p256_mulm); the form below elsewhere.
    ? ( nurl_p256_mulm ( vec_data [i] dst ) ( vec_data [i] a ) ( vec_data [i] b ) ) {} { ( _p256_mul_port scr dst a b ) }
}

// The multiply as NURL, for a target with no kernel (and the reference
// compiler/tests/p256_kernel_agrees.nu holds the kernels to).
@ __p256_mul_port_p * i op * i ap * i bp → v {
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
    = . op 0 # i o0
    = . op 1 # i o1
    = . op 2 # i o2
    = . op 3 # i o3
}

// requires: every field-element operand (dst included) holds 4 limbs.
raw @ _p256_mul_port P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v { ( __p256_mul_port_p ( vec_data [i] dst ) ( vec_data [i] a ) ( vec_data [i] b ) ) }

// (kept: the 9-limb staging cond-sub is gone — add/sub carry in
// registers now and fold the conditional ±p inline, like the multiply.)

// Montgomery SQUARE: dst ← (a·a·R^-1) mod p. The 16-product schoolbook
// collapses to 10 — six cross products doubled by one carry-chained
// shift, plus the four diagonals — followed by the same four rounds of
// sparse-p Montgomery reduction the multiply runs and the same
// constant-time conditional subtract. Everything the point formulas
// spell as `mul x x` comes through here: 37% of a fixed-base comb's
// field ops are squarings.
// `dst` may alias `a` — the limbs are read into locals first.
// requires: every field-element operand (dst included) holds 4 limbs.
raw @ _p256_sqr_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    // The register kernel where the target has one (nurl_p256_sqrm).
    ? ( nurl_p256_sqrm ( vec_data [i] dst ) ( vec_data [i] a ) ) {} { ( _p256_sqr_port scr dst a ) }
}

// The square as NURL (as _p256_mul_port).
@ __p256_sqr_port_p * i op * i ap → v {
    : u64 a0 # u64 . ap 0
    : u64 a1 # u64 . ap 1
    : u64 a2 # u64 . ap 2
    : u64 a3 # u64 . ap 3
    // ── cross products: r1..r6 = a0a1, a0a2, a0a3(+a1a2), a1a3, a2a3 ──
    : ~ u64 cr 0
    : ~ u64 r1 ( nurl_mac_lo a0 a1 0 0 )
    = cr ( nurl_mac_hi a0 a1 0 0 )
    : ~ u64 r2 ( nurl_mac_lo a0 a2 0 cr )
    = cr ( nurl_mac_hi a0 a2 0 cr )
    : ~ u64 r3 ( nurl_mac_lo a0 a3 0 cr )
    : ~ u64 r4 ( nurl_mac_hi a0 a3 0 cr )
    : u64 s3 ( nurl_mac_lo a1 a2 r3 0 )
    = cr ( nurl_mac_hi a1 a2 r3 0 )
    = r3 s3
    : u64 s4 ( nurl_mac_lo a1 a3 r4 cr )
    : ~ u64 r5 ( nurl_mac_hi a1 a3 r4 cr )
    = r4 s4
    : u64 s5 ( nurl_mac_lo a2 a3 r5 0 )
    : ~ u64 r6 ( nurl_mac_hi a2 a3 r5 0 )
    = r5 s5
    // ── double the cross terms, carry chaining into r7 ──
    : u64 d1 ( nurl_addc_lo r1 r1 0 )
    = cr ( nurl_addc_hi r1 r1 0 )
    : u64 d2 ( nurl_addc_lo r2 r2 cr )
    = cr ( nurl_addc_hi r2 r2 cr )
    : u64 d3 ( nurl_addc_lo r3 r3 cr )
    = cr ( nurl_addc_hi r3 r3 cr )
    : u64 d4 ( nurl_addc_lo r4 r4 cr )
    = cr ( nurl_addc_hi r4 r4 cr )
    : u64 d5 ( nurl_addc_lo r5 r5 cr )
    = cr ( nurl_addc_hi r5 r5 cr )
    : u64 d6 ( nurl_addc_lo r6 r6 cr )
    : ~ u64 r7 ( nurl_addc_hi r6 r6 cr )
    // ── diagonals a0², a1², a2², a3² at the even positions ──
    : ~ u64 r0 ( nurl_mac_lo a0 a0 0 0 )
    = cr ( nurl_mac_hi a0 a0 0 0 )
    = r1 ( nurl_addc_lo d1 cr 0 )
    = cr ( nurl_addc_hi d1 cr 0 )
    = r2 ( nurl_mac_lo a1 a1 d2 cr )
    = cr ( nurl_mac_hi a1 a1 d2 cr )
    = r3 ( nurl_addc_lo d3 cr 0 )
    = cr ( nurl_addc_hi d3 cr 0 )
    = r4 ( nurl_mac_lo a2 a2 d4 cr )
    = cr ( nurl_mac_hi a2 a2 d4 cr )
    = r5 ( nurl_addc_lo d5 cr 0 )
    = cr ( nurl_addc_hi d5 cr 0 )
    = r6 ( nurl_mac_lo a3 a3 d6 cr )
    = cr ( nurl_mac_hi a3 a3 d6 cr )
    // the full square is < 2^512, so this last add cannot overflow.
    = r7 + r7 cr
    // ── 4 rounds of Montgomery reduction: m = low word, add m·p, shift ──
    // Same sparse-p folds as _p256_mul_d; the carry lands in r[i+4] and
    // ripples upward through an extra top word `ex` (≤ 4 by the 2p bound).
    : ~ u64 ex 0
    : ~ u64 m 0
    // round 0 — m·p added at r0..r3, carry into r4..r7,ex
    = m r0
    = cr ( nurl_mac_hi m 18446744073709551615 r0 0 )
    : u64 u01 ( nurl_mac_lo m 4294967295 r1 cr )
    = cr ( nurl_mac_hi m 4294967295 r1 cr )
    = r1 u01
    : u64 u02 ( nurl_addc_lo r2 cr 0 )
    = cr ( nurl_addc_hi r2 cr 0 )
    = r2 u02
    : u64 u03 ( nurl_mac_lo m 18446744069414584321 r3 cr )
    = cr ( nurl_mac_hi m 18446744069414584321 r3 cr )
    = r3 u03
    : u64 u04 ( nurl_addc_lo r4 cr 0 )
    = cr ( nurl_addc_hi r4 cr 0 )
    = r4 u04
    : u64 u05 ( nurl_addc_lo r5 cr 0 )
    = cr ( nurl_addc_hi r5 cr 0 )
    = r5 u05
    : u64 u06 ( nurl_addc_lo r6 cr 0 )
    = cr ( nurl_addc_hi r6 cr 0 )
    = r6 u06
    : u64 u07 ( nurl_addc_lo r7 cr 0 )
    = cr ( nurl_addc_hi r7 cr 0 )
    = r7 u07
    = ex + ex cr
    // round 1 — at r1..r4, carry r5..r7,ex
    = m r1
    = cr ( nurl_mac_hi m 18446744073709551615 r1 0 )
    : u64 u11 ( nurl_mac_lo m 4294967295 r2 cr )
    = cr ( nurl_mac_hi m 4294967295 r2 cr )
    = r2 u11
    : u64 u12 ( nurl_addc_lo r3 cr 0 )
    = cr ( nurl_addc_hi r3 cr 0 )
    = r3 u12
    : u64 u13 ( nurl_mac_lo m 18446744069414584321 r4 cr )
    = cr ( nurl_mac_hi m 18446744069414584321 r4 cr )
    = r4 u13
    : u64 u14 ( nurl_addc_lo r5 cr 0 )
    = cr ( nurl_addc_hi r5 cr 0 )
    = r5 u14
    : u64 u15 ( nurl_addc_lo r6 cr 0 )
    = cr ( nurl_addc_hi r6 cr 0 )
    = r6 u15
    : u64 u16 ( nurl_addc_lo r7 cr 0 )
    = cr ( nurl_addc_hi r7 cr 0 )
    = r7 u16
    = ex + ex cr
    // round 2 — at r2..r5, carry r6..r7,ex
    = m r2
    = cr ( nurl_mac_hi m 18446744073709551615 r2 0 )
    : u64 u21 ( nurl_mac_lo m 4294967295 r3 cr )
    = cr ( nurl_mac_hi m 4294967295 r3 cr )
    = r3 u21
    : u64 u22 ( nurl_addc_lo r4 cr 0 )
    = cr ( nurl_addc_hi r4 cr 0 )
    = r4 u22
    : u64 u23 ( nurl_mac_lo m 18446744069414584321 r5 cr )
    = cr ( nurl_mac_hi m 18446744069414584321 r5 cr )
    = r5 u23
    : u64 u24 ( nurl_addc_lo r6 cr 0 )
    = cr ( nurl_addc_hi r6 cr 0 )
    = r6 u24
    : u64 u25 ( nurl_addc_lo r7 cr 0 )
    = cr ( nurl_addc_hi r7 cr 0 )
    = r7 u25
    = ex + ex cr
    // round 3 — at r3..r6, carry r7,ex
    = m r3
    = cr ( nurl_mac_hi m 18446744073709551615 r3 0 )
    : u64 u31 ( nurl_mac_lo m 4294967295 r4 cr )
    = cr ( nurl_mac_hi m 4294967295 r4 cr )
    = r4 u31
    : u64 u32 ( nurl_addc_lo r5 cr 0 )
    = cr ( nurl_addc_hi r5 cr 0 )
    = r5 u32
    : u64 u33 ( nurl_mac_lo m 18446744069414584321 r6 cr )
    = cr ( nurl_mac_hi m 18446744069414584321 r6 cr )
    = r6 u33
    : u64 u34 ( nurl_addc_lo r7 cr 0 )
    = cr ( nurl_addc_hi r7 cr 0 )
    = r7 u34
    = ex + ex cr
    // ── result = r4..r7 (+ex), value < 2p: same ct subtract as the mul ──
    : u64 d0 ( nurl_subb_lo r4 18446744073709551615 0 )
    : ~ u64 bb ( nurl_subb_hi r4 18446744073709551615 0 )
    : u64 e1 ( nurl_subb_lo r5 4294967295 bb )
    = bb ( nurl_subb_hi r5 4294967295 bb )
    : u64 e2 ( nurl_subb_lo r6 0 bb )
    = bb ( nurl_subb_hi r6 0 bb )
    : u64 e3 ( nurl_subb_lo r7 18446744069414584321 bb )
    = bb ( nurl_subb_hi r7 18446744069414584321 bb )
    : i topb - # i ex # i bb
    : u64 mask ? < topb 0 0 18446744073709551615
    : u64 imask ^^ mask 18446744073709551615
    : u64 o0 | & mask d0 & imask r4
    : u64 o1 | & mask e1 & imask r5
    : u64 o2 | & mask e2 & imask r6
    : u64 o3 | & mask e3 & imask r7
    = . op 0 # i o0
    = . op 1 # i o1
    = . op 2 # i o2
    = . op 3 # i o3
}

// requires: every field-element operand (dst included) holds 4 limbs.
raw @ _p256_sqr_port P256Scratch scr ( Vec i ) dst ( Vec i ) a → v { ( __p256_sqr_port_p ( vec_data [i] dst ) ( vec_data [i] a ) ) }

// (a + b) mod p, constant-time. a, b < p ⇒ a+b < 2p ⇒ one conditional sub.
// requires: a and b hold 4 limbs.
raw @ p256ct_add ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_add_s scr a b )
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
inline @ __p256_add_p * i op * i ap * i bp → v {
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
    // The fifth word's borrow: 1 exactly when cc:t < p, i.e. t is the sum.
    : u64 keep ( nurl_subb_hi cc 0 bb )
    : u64 m - 0 keep
    = . op 0 # i ^^ d0 & m ^^ d0 t0
    = . op 1 # i ^^ d1 & m ^^ d1 t1
    = . op 2 # i ^^ d2 & m ^^ d2 t2
    = . op 3 # i ^^ d3 & m ^^ d3 t3
}

@ __p256_add_d P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v { ( __p256_add_p ( vec_data [i] dst ) ( vec_data [i] a ) ( vec_data [i] b ) ) }

// (a − b) mod p, constant-time: a − b, and if it borrows add p back.
// requires: a and b hold 4 limbs.
raw @ p256ct_sub ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_sub_s scr a b )
    ^ r
}

@ __p256_sub_s P256Scratch scr ( Vec i ) a ( Vec i ) b → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
    ( __p256_sub_d scr out a b )
    ^ out
}

// a − b with borrow, then a masked add-back of p when it underflowed.
// `dst` may alias a and/or b.
inline @ __p256_sub_p * i op * i ap * i bp → v {
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
    = . op 0 # i r0
    = . op 1 # i r1
    = . op 2 # i r2
    = . op 3 # i r3
}

@ __p256_sub_d P256Scratch scr ( Vec i ) dst ( Vec i ) a ( Vec i ) b → v { ( __p256_sub_p ( vec_data [i] dst ) ( vec_data [i] a ) ( vec_data [i] b ) ) }

// requires: a holds 4 limbs.
raw @ p256ct_sqr ( Vec i ) a → ( Vec i ) { ^ ( p256ct_mul a a ) }

// requires: a holds 4 limbs.
raw @ p256ct_to_mont ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( _p256_to_mont_s scr a )
    ^ r
}

// requires: a holds 4 limbs.
raw @ _p256_to_mont_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
    ( _p256_to_mont_d scr out a )
    ^ out
}

// requires: every field-element operand (dst included) holds 4 limbs.
raw @ _p256_to_mont_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    : ( Vec i ) r2 ( __p256_r2 )
    ( _p256_mul_d scr dst a r2 )
}

// requires: a holds 4 limbs.
raw @ p256ct_from_mont ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_from_mont_s scr a )
    ^ r
}

@ __p256_from_mont_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
    ( _p256_from_mont_d scr out a )
    ^ out
}

// requires: every field-element operand (dst included) holds 4 limbs.
raw @ _p256_from_mont_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    : ( Vec i ) one ( __p256_one )
    ( _p256_mul_d scr dst a one )
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
    ^ r
}

@ _p256_one_mont_s P256Scratch scr → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
    ( _p256_one_mont_d scr out )
    ^ out
}

// requires: dst holds 4 limbs.
raw @ _p256_one_mont_d P256Scratch scr ( Vec i ) dst → v {
    : ( Vec i ) one ( __p256_one )
    ( _p256_to_mont_d scr dst one )
}

// Modular inverse in Montgomery form (_p256_inv_d): a·R ↦ a⁻¹·R mod p,
// constant time. For a == 0 returns 0.
// requires: a holds 4 limbs.
raw @ p256ct_inv ( Vec i ) a → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) r ( __p256_inv_s scr a )
    ^ r
}

@ __p256_inv_s P256Scratch scr ( Vec i ) a → ( Vec i ) {
    : ( Vec i ) out ( _mag4 )
    ( _p256_inv_d scr out a )
    ^ out
}

// dst ← a⁻¹ in Montgomery form (0 for 0): the divsteps of std/modinv
// over p (−1 + 2^34·2^62 + (2^6 − 2^38)·2^186 + 256·2^248 in signed-62
// form) invert aR to a⁻¹R⁻¹, and a Montgomery multiply by R³ makes that
// a⁻¹R. Constant time; dst may alias a. It replaces Fermat's a^(p−2),
// 255 squarings and 13 multiplies, a serial chain of their latencies.
// requires: every field-element operand (dst included) holds 4 limbs.
raw @ _p256_inv_d P256Scratch scr ( Vec i ) dst ( Vec i ) a → v {
    : *i ap ( vec_data [i] a )
    : ~ u64 o0 0
    : ~ u64 o1 0
    : ~ u64 o2 0
    : ~ u64 o3 0
    ( _modinv256 o0 o1 o2 o3 # u64 . ap 0 # u64 . ap 1 # u64 . ap 2 # u64 . ap 3 -1 17179869184 0 -274877906880 256 4611686018427387903 )
    : *i dp ( vec_data [i] dst )
    = . dp 0 # i o0 = . dp 1 # i o1 = . dp 2 # i o2 = . dp 3 # i o3
    // R³ mod p
    : ( Vec i ) r3 ( _mag4 )
    : *i rp ( vec_data [i] r3 )
    : u64 c0 18446744060824649738
    : u64 c1 18446743996400140279
    = . rp 0 # i c0 = . rp 1 # i c1 = . rp 2 25769803772 = . rp 3 103079215105
    ( _p256_mul_d scr dst dst r3 )
}

// 4-limb copy.
@ __p256_cp ( Vec i ) dst ( Vec i ) a → v {
    : *i op ( vec_data [i] dst )
    : *i ap ( vec_data [i] a )
    = . op 0 . ap 0
    = . op 1 . ap 1
    = . op 2 . ap 2
    = . op 3 . ap 3
}

// ── constant-time P-256 point arithmetic (homogeneous projective) ──────
// Points are (X : Y : Z), x = X/Z, y = Y/Z, identity = (0 : 1 : 0); every
// coordinate is an 8-limb Montgomery field element. Addition uses the Renes–
// Costello–Batina COMPLETE formula (a = −3) — correct for ALL inputs incl.
// the identity and P = Q, with no branch — so the scalar-multiply ladder is
// fully constant-time (verified against `cryptography`'s P-256 in Python and
// cross-checked against the bigint reference). a / b3 are passed in Montgomery
// form (curve constants, computed once per scalar-mult).

raw : P256Pt { ( Vec i ) x ( Vec i ) y ( Vec i ) z }

// An uninitialised point (three 8-limb magnitudes) — a ladder register.
// requires: every coordinate is written before it is read (they start
// uninitialised).
raw @ _p256_pt_mag → P256Pt {
    ^ @ P256Pt { ( _mag4 ) ( _mag4 ) ( _mag4 ) }
}

// requires: a and b are points of 4-limb coordinates.
raw @ p256ct_pt_select i bit P256Pt a P256Pt b → P256Pt {
    : P256Pt out ( _p256_pt_mag )
    ( p256ct_pt_select_d out bit a b )
    ^ out
}

// `dst` may alias `a` or `b`: the merge reads and writes one limb index at
// a time.
// requires: dst, a and b are points of 4-limb coordinates.
raw @ p256ct_pt_select_d P256Pt dst i bit P256Pt a P256Pt b → v {
    : i mask - 0 bit
    : i imask - 0 - 1 bit
    ( __p256_lmerge_d . dst x mask imask . a x . b x )
    ( __p256_lmerge_d . dst y mask imask . a y . b y )
    ( __p256_lmerge_d . dst z mask imask . a z . b z )
}

inline @ __p256_lmerge_p * i op i mask i imask * i ap * i bp → v {
    = . op 0 | & mask . ap 0 & imask . bp 0
    = . op 1 | & mask . ap 1 & imask . bp 1
    = . op 2 | & mask . ap 2 & imask . bp 2
    = . op 3 | & mask . ap 3 & imask . bp 3
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

// requires: p's coordinates hold 4 limbs.
raw @ p256ct_pt_clone P256Pt p → P256Pt {
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
// requires: dst's coordinates hold 4 limbs.
raw @ _p256_set_identity_d P256Scratch scr P256Pt dst → v {
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
//     degenerates. Its callers rule the case out instead: the fixed-base
//     comb and the variable-base ladder below each carry the proof that, for a scalar
//     reduced mod n, no addition they make can meet it.
//
// All limb traffic stays masked and fixed-count: same constant-time
// discipline as the projective path.

// Jacobian doubling in place, a = −3 (dbl-2001-b): 3M+5S.
// Registers: g0=delta g1=gamma g2=beta g3=alpha g4/g5=temps.
// requires: scr from _p256_scr_new, its registers unshrunk; pt's coordinates
// hold 4 limbs.
raw @ _p256_jdbl_d P256Scratch scr P256Pt pt → v {
    : *i xr ( vec_data [i] . pt x )
    : *i yr ( vec_data [i] . pt y )
    : *i zr ( vec_data [i] . pt z )
    : *i delta ( vec_data [i] . scr g0 )
    : *i gamma ( vec_data [i] . scr g1 )
    : *i beta ( vec_data [i] . scr g2 )
    : *i alpha ( vec_data [i] . scr g3 )
    : *i t4 ( vec_data [i] . scr g4 )
    : *i t5 ( vec_data [i] . scr g5 )
    ( __p256_sqr_p delta zr )
    ( __p256_sqr_p gamma yr )
    ( __p256_mul_p beta xr gamma )
    // alpha = 3·(xr − delta)·(xr + delta)
    ( __p256_sub_p t4 xr delta )
    ( __p256_add_p t5 xr delta )
    ( __p256_mul_p alpha t4 t5 )
    ( __p256_add_p t4 alpha alpha )
    ( __p256_add_p alpha t4 alpha )
    // Z3 = (yr + zr)² − gamma − delta   (before xr/yr are overwritten)
    ( __p256_add_p t4 yr zr )
    ( __p256_sqr_p t4 t4 )
    ( __p256_sub_p t4 t4 gamma )
    ( __p256_sub_p zr t4 delta )
    // X3 = alpha² − 8·beta
    ( __p256_sqr_p t4 alpha )
    ( __p256_add_p t5 beta beta )
    ( __p256_add_p t5 t5 t5 )
    ( __p256_add_p delta t5 t5 )
    ( __p256_sub_p xr t4 delta )
    // Y3 = alpha·(4·beta − X3) − 8·gamma²
    ( __p256_sub_p t4 t5 xr )
    ( __p256_mul_p t4 alpha t4 )
    ( __p256_sqr_p t5 gamma )
    ( __p256_add_p t5 t5 t5 )
    ( __p256_add_p t5 t5 t5 )
    ( __p256_add_p t5 t5 t5 )
    ( __p256_sub_p yr t4 t5 )
}

// Branch-free "all four limbs zero" mask: −1 when v == 0, else 0.
// requires: v holds 4 limbs.
raw @ _p256_zmask ( Vec i ) v → i {
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
// requires: scr from _p256_scr_new, its registers unshrunk; acc's
// coordinates, x2, y2 and one_m hold 4 limbs.
raw @ _p256_jmadd_d P256Scratch scr P256Pt acc ( Vec i ) x2 ( Vec i ) y2 ( Vec i ) one_m i keep → v {
    : *i X1 ( vec_data [i] . acc x )
    : *i Y1 ( vec_data [i] . acc y )
    : *i Z1 ( vec_data [i] . acc z )
    : *i px2 ( vec_data [i] x2 )
    : *i py2 ( vec_data [i] y2 )
    : *i pone ( vec_data [i] one_m )
    : *i z3 ( vec_data [i] . scr g0 )
    : *i hreg ( vec_data [i] . scr g1 )
    : *i rreg ( vec_data [i] . scr g2 )
    : *i hh ( vec_data [i] . scr g3 )
    : *i x3 ( vec_data [i] . scr g4 )
    : *i vv ( vec_data [i] . scr g5 )
    : *i t ( vec_data [i] . scr gp )
    : i inf_mask ( _p256_zmask . acc z )
    // zz = Z1²; u2 = x2·zz; s2 = y2·Z1·zz
    ( __p256_sqr_p z3 Z1 )
    ( __p256_mul_p hreg px2 z3 )
    ( __p256_mul_p t z3 Z1 )
    ( __p256_mul_p rreg py2 t )
    // H = u2 − X1; R = s2 − Y1
    ( __p256_sub_p hreg hreg X1 )
    ( __p256_sub_p rreg rreg Y1 )
    // Z3 = Z1·H (into its own register — acc stays whole until commit)
    ( __p256_mul_p z3 Z1 hreg )
    // hh = H²; V = X1·hh; X3 = R² − H³ − 2V. 2V is formed while H³ is
    // still being multiplied (t is free between s2 and Y1·H³), so X3
    // waits on H³ for two subtractions, not three.
    ( __p256_sqr_p hh hreg )
    ( __p256_mul_p vv X1 hh )
    ( __p256_add_p t vv vv )
    ( __p256_sqr_p x3 rreg )
    ( __p256_mul_p hh hreg hh )
    ( __p256_sub_p x3 x3 hh )
    ( __p256_sub_p x3 x3 t )
    // Y3 = R·(V − X3) − Y1·H³
    ( __p256_sub_p vv vv x3 )
    ( __p256_mul_p vv rreg vv )
    ( __p256_mul_p t Y1 hh )
    ( __p256_sub_p vv vv t )
    // Masked two-stage commit: result ← (∞ ? affine : computed), then
    // acc ← (keep ? acc : result). Element-wise merges, no branches.
    : i ninf ^^ inf_mask - 0 1
    : i nkeep ^^ keep - 0 1
    ( __p256_lmerge_p x3 inf_mask ninf px2 x3 )
    ( __p256_lmerge_p vv inf_mask ninf py2 vv )
    ( __p256_lmerge_p z3 inf_mask ninf pone z3 )
    ( __p256_lmerge_p X1 nkeep keep x3 X1 )
    ( __p256_lmerge_p Y1 nkeep keep vv Y1 )
    ( __p256_lmerge_p Z1 nkeep keep z3 Z1 )
}

// ── affine window table (fixed-base comb) ─────────────────────────────
// Affine Montgomery multiples of G: entry d occupies [d·8, d·8+8) as
// x‖y. Entry 0 is all-zero — the comb never COMMITS it (digit 0 keeps
// the accumulator via _p256_jmadd_d's mask), but the scan still reads
// it so the trace is digit-independent.

// requires: ax and ay hold 4 limbs, and 0 ≤ d with 8·d + 8 ≤ vec_len tbl.
raw @ _p256_atbl_put ( Vec i ) tbl i d ( Vec i ) ax ( Vec i ) ay → v {
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

// Constant-time masked read of entry `digit` into (ex, ey). `digit` is
// four bits of a SECRET scalar, so this must not become an indexed load:
// it reads all sixteen entries, every time, and merges each one under a
// mask that is all-ones exactly when d == digit. The mask is arithmetic,
// not a comparison — `d ^ digit` is zero only on a match, and subtracting
// one from zero borrows into the top bit, which nothing else can set for
// a 4-bit value. No branch, and the address stream is identical for every
// possible digit.
// requires: ex and ey hold 4 limbs, and tbl holds 16 entries (128 limbs).
raw @ _p256_atbl_get_d ( Vec i ) ex ( Vec i ) ey ( Vec i ) tbl i digit → v {
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

// ── Jacobian point storage ────────────────────────────────────────────
// A point stored into a flat limb vector at slot d: [d·12, d·12+12) as
// x‖y‖z — the Jacobian multiples _p256_affine_multiples builds before it
// normalises them.

// requires: p's coordinates hold 4 limbs, and 0 ≤ d with 12·d + 12 ≤ vec_len
// tbl.
raw @ _p256_tbl_put ( Vec i ) tbl i d P256Pt p → v {
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

// The point at slot d of such a flat vector, into `dst`.
// requires: dst's coordinates hold 4 limbs, and 0 ≤ d with 12·d + 12 ≤
// vec_len tbl.
raw @ _p256_tbl_get P256Pt dst ( Vec i ) tbl i d → v {
    : *i tp ( vec_data [i] tbl )
    : i base * d 12
    ( __p256_ld4 . dst x # *i + # i tp * base 8 )
    ( __p256_ld4 . dst y # *i + # i tp * + base 4 8 )
    ( __p256_ld4 . dst z # *i + # i tp * + base 8 8 )
}

// ── variable-base scalar multiplication ──────────────────────────────
//
// k·Q for a point Q the caller supplies (ECDH against a peer's share), on
// the same Jacobian machinery as the fixed-base comb: 3M+5S doublings and
// 8M+3S mixed additions against an AFFINE table 1·Q … 15·Q, where the
// complete projective formula this replaces spent 14 multiplies on every
// one of 334 operations.
//
// Complete for every scalar, by construction rather than by masking. The
// scalar is first reduced mod n (constant time). Before each addition the
// accumulator is m·Q with m = 16 × (the windows consumed so far), so
// either m = 0 — acc = ∞, which the mixed addition commits as the entry
// — or 16 ≤ m < n. The entry is d·Q with 1 ≤ d ≤ 15, so acc = entry
// (m ≡ d mod n), the one case the mixed addition cannot compute, is
// impossible; acc = −entry would need m = n − d, whose sum is n·Q — a
// scalar of n, excluded by the reduction (and the formula yields Z = 0
// for it regardless). Without the reduction a crafted scalar reaches the
// degenerate case: k = n + 30 lands the last window on acc = 15·Q =
// entry 15 (n ≡ 1 mod 16).
//
// The table is built from Q in Jacobian form (one doubling, thirteen mixed
// additions — never degenerate, since (d−1)·Q = ±Q would need d ≡ 0 or 2
// mod n) and normalised to affine with ONE field inversion by Montgomery's
// batch trick. Constant-time in the scalar: 64 windows, each four
// doublings, one read of all sixteen table entries under a mask, and one
// masked commit.

// b (the curve coefficient), plain limbs.
@ _p256_b_plain → ( Vec i ) {
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0x3BCE3C3E27D2604B = . q 1 # i 0x651D06B0CC53B0F6
    = . q 2 # i 0xB3EBBD55769886BC = . q 3 # i 0x5AC635D8AA3A93E7
    ^ v
}

// v < p (plain limbs): the subtraction v − p borrows out of the top word.
// requires: v holds 4 limbs.
raw @ _p256_lt_p ( Vec i ) v → b {
    : *i vp ( vec_data [i] v )
    : ~ u64 bb ( nurl_subb_hi # u64 . vp 0 18446744073709551615 0 )
    = bb ( nurl_subb_hi # u64 . vp 1 4294967295 bb )
    = bb ( nurl_subb_hi # u64 . vp 2 0 bb )
    = bb ( nurl_subb_hi # u64 . vp 3 18446744069414584321 bb )
    ^ != # i bb 0
}

// Do two field elements hold the same value? Every _d worker returns a
// canonical residue, so limb equality is value equality.
// requires: a and b hold 4 limbs.
raw @ _p256_eq ( Vec i ) a ( Vec i ) b → b {
    : *i ap ( vec_data [i] a )
    : *i bp ( vec_data [i] b )
    : i d | | | ^^ . ap 0 . bp 0 ^^ . ap 1 . bp 1 ^^ . ap 2 . bp 2 ^^ . ap 3 . bp 3
    ^ == d 0
}

// Is the Montgomery affine point (x, y) on y² = x³ − 3x + b?
// requires: xm and ym hold 4 limbs.
raw @ _p256_on_curve P256Scratch scr ( Vec i ) xm ( Vec i ) ym → b {
    : ( Vec i ) lhs ( _mag4 )
    : ( Vec i ) rhs ( _mag4 )
    : ( Vec i ) t ( _mag4 )
    ( _p256_sqr_d scr lhs ym )
    ( _p256_sqr_d scr rhs xm )
    ( _p256_mul_d scr rhs rhs xm )
    ( __p256_add_d scr t xm xm )
    ( __p256_add_d scr t t xm )
    ( __p256_sub_d scr rhs rhs t )
    : ( Vec i ) bm ( _p256_to_mont_s scr ( _p256_b_plain ) )
    ( __p256_add_d scr rhs rhs bm )
    ^ ( _p256_eq lhs rhs )
}

// Mixed addition for PUBLIC operands (signature verification): exact in
// every case, by branching — acc = ∞ takes the entry, acc = entry
// doubles, acc = −entry becomes ∞. Variable time, which public data
// allows; never call it with a secret scalar's digits.
// requires: scr from _p256_scr_new, its registers unshrunk; acc's
// coordinates, x2, y2 and one_m hold 4 limbs.
raw @ _p256_jmadd_vt P256Scratch scr P256Pt acc ( Vec i ) x2 ( Vec i ) y2 ( Vec i ) one_m → v {
    : ( Vec i ) X1 . acc x
    : ( Vec i ) Y1 . acc y
    : ( Vec i ) Z1 . acc z
    ? != ( _p256_zmask Z1 ) 0 {
        ( __p256_copy_d X1 x2 ) ( __p256_copy_d Y1 y2 ) ( __p256_copy_d Z1 one_m )
        ^
    } {}
    : ( Vec i ) z3 . scr g0
    : ( Vec i ) hreg . scr g1
    : ( Vec i ) rreg . scr g2
    : ( Vec i ) hh . scr g3
    : ( Vec i ) x3 . scr g4
    : ( Vec i ) vv . scr g5
    : ( Vec i ) t . scr gp
    ( _p256_sqr_d scr z3 Z1 )
    ( _p256_mul_d scr hreg x2 z3 )
    ( _p256_mul_d scr t z3 Z1 )
    ( _p256_mul_d scr rreg y2 t )
    ( __p256_sub_d scr hreg hreg X1 )
    ( __p256_sub_d scr rreg rreg Y1 )
    ? != ( _p256_zmask hreg ) 0 {
        ? != ( _p256_zmask rreg ) 0 { ( _p256_jdbl_d scr acc ) } {
            : *i zp ( vec_data [i] Z1 )
            = . zp 0 0 = . zp 1 0 = . zp 2 0 = . zp 3 0
        }
        ^
    } {}
    ( _p256_mul_d scr z3 Z1 hreg )
    ( _p256_sqr_d scr hh hreg )
    ( _p256_mul_d scr vv X1 hh )
    ( _p256_sqr_d scr x3 rreg )
    ( _p256_mul_d scr hh hreg hh )
    ( __p256_sub_d scr x3 x3 hh )
    ( __p256_sub_d scr x3 x3 vv )
    ( __p256_sub_d scr x3 x3 vv )
    ( __p256_sub_d scr vv vv x3 )
    ( _p256_mul_d scr vv rreg vv )
    ( _p256_mul_d scr t Y1 hh )
    ( __p256_sub_d scr vv vv t )
    ( __p256_copy_d X1 x3 ) ( __p256_copy_d Y1 vv ) ( __p256_copy_d Z1 z3 )
}

// Four limbs at `src` into `dst`.
@ __p256_ld4 ( Vec i ) dst * i src → v {
    : *i dp ( vec_data [i] dst )
    = . dp 0 . src 0 = . dp 1 . src 1 = . dp 2 . src 2 = . dp 3 . src 3
}

// Jacobian += Jacobian (add-1998-cmo-2: 12M+4S), for PUBLIC points whose
// relation is known: neither is ∞ and acc ≠ ±q. Nothing here checks it —
// H = 0 would give Z = 0 — so it is for the fixed-base table builder
// alone, where every call is an (j−1)·B + B with 3 ≤ j ≤ 15, which is
// neither case. Uses every scratch register.
// requires: scr from _p256_scr_new, its registers unshrunk; acc's and q's
// coordinates hold 4 limbs.
raw @ _p256_jadd_d P256Scratch scr P256Pt acc P256Pt q → v {
    : ( Vec i ) X1 . acc x
    : ( Vec i ) Y1 . acc y
    : ( Vec i ) Z1 . acc z
    : ( Vec i ) u1 . scr g0
    : ( Vec i ) hreg . scr g1
    : ( Vec i ) s1 . scr g2
    : ( Vec i ) rreg . scr g3
    : ( Vec i ) hh . scr g4
    : ( Vec i ) vv . scr g5
    : ( Vec i ) t . scr gp
    // U1 = X1·Z2², S1 = Y1·Z2³; U2 = X2·Z1², S2 = Y2·Z1³
    ( _p256_sqr_d scr t . q z )
    ( _p256_mul_d scr u1 X1 t )
    ( _p256_mul_d scr t t . q z )
    ( _p256_mul_d scr s1 Y1 t )
    ( _p256_sqr_d scr t Z1 )
    ( _p256_mul_d scr hreg . q x t )
    ( _p256_mul_d scr t t Z1 )
    ( _p256_mul_d scr rreg . q y t )
    // H = U2 − U1, R = S2 − S1; Z3 = Z1·Z2·H
    ( __p256_sub_d scr hreg hreg u1 )
    ( __p256_sub_d scr rreg rreg s1 )
    ( _p256_mul_d scr Z1 Z1 . q z )
    ( _p256_mul_d scr Z1 Z1 hreg )
    // V = U1·H², H³; X3 = R² − H³ − 2V; Y3 = R·(V − X3) − S1·H³
    ( _p256_sqr_d scr hh hreg )
    ( _p256_mul_d scr vv u1 hh )
    ( _p256_mul_d scr hh hh hreg )
    ( _p256_sqr_d scr X1 rreg )
    ( __p256_sub_d scr X1 X1 hh )
    ( __p256_sub_d scr X1 X1 vv )
    ( __p256_sub_d scr X1 X1 vv )
    ( __p256_sub_d scr vv vv X1 )
    ( _p256_mul_d scr vv rreg vv )
    ( _p256_mul_d scr t s1 hh )
    ( __p256_sub_d scr Y1 vv t )
}

// `count` Jacobian points (flat x‖y‖z, 12 limbs each, none of them ∞) into
// affine entries of `tbl` (x‖y, 8 limbs each) at slots at … at+count−1,
// with ONE field inversion: Montgomery's trick — prefix products
// c_k = Z_0·…·Z_k, invert the last, then back down: z_k⁻¹ = inv·c_(k−1),
// inv ← inv·Z_k. Public points only (the loop is fixed-count anyway).
// requires: scr from _p256_scr_new, its registers unshrunk; jac holds count
// points (12·count limbs), one_m 4 limbs, and tbl the slots
// at … at + count − 1 (8 limbs each).
raw @ _p256_batch_affine P256Scratch scr ( Vec i ) jac i count ( Vec i ) tbl i at ( Vec i ) one_m → v {
    : *i jp ( vec_data [i] jac )
    : ( Vec i ) pre ( _magn * count 4 )
    : *i pp ( vec_data [i] pre )
    : ( Vec i ) za ( _mag4 )
    : ( Vec i ) acc ( _mag4 )
    ( __p256_copy_d acc one_m )
    : ~ i k 0
    ~ < k count {
        ( __p256_ld4 za # *i + # i jp * + * k 12 8 8 )
        ( _p256_mul_d scr acc acc za )
        : *i ap ( vec_data [i] acc )
        : i b * k 4
        = . pp b . ap 0 = . pp + b 1 . ap 1 = . pp + b 2 . ap 2 = . pp + b 3 . ap 3
        = k + k 1
    }
    : ( Vec i ) inv ( _mag4 )
    ( _p256_inv_d scr inv acc )
    : ( Vec i ) zi ( _mag4 )
    : ( Vec i ) zi2 ( _mag4 )
    : ( Vec i ) xa ( _mag4 )
    : ( Vec i ) ya ( _mag4 )
    : ( Vec i ) prev ( _mag4 )
    = k - count 1
    ~ >= k 0 {
        ? > k 0 {
            ( __p256_ld4 prev # *i + # i pp * * - k 1 4 8 )
            ( _p256_mul_d scr zi inv prev )
        } { ( __p256_copy_d zi inv ) }
        ( __p256_ld4 za # *i + # i jp * + * k 12 8 8 )
        ( _p256_mul_d scr inv inv za )
        ( __p256_ld4 xa # *i + # i jp * * k 12 8 )
        ( __p256_ld4 ya # *i + # i jp * + * k 12 4 8 )
        ( _p256_sqr_d scr zi2 zi )
        ( _p256_mul_d scr xa xa zi2 )
        ( _p256_mul_d scr zi2 zi2 zi )
        ( _p256_mul_d scr ya ya zi2 )
        ( _p256_atbl_put tbl + at k xa ya )
        = k - k 1
    }
}

// The affine table 0, 1·Q, …, 15·Q (entry 0 all-zero, never committed) for
// a Montgomery affine Q of order n: Jacobian multiples, then one batch
// inversion. Q is public in every use (a peer's share, a public key, G).
// requires: scr from _p256_scr_new, its registers unshrunk; qx, qy and one_m
// hold 4 limbs.
raw @ _p256_affine_multiples P256Scratch scr ( Vec i ) qx ( Vec i ) qy ( Vec i ) one_m → ( Vec i ) {
    // Jacobian 1·Q … 15·Q, flat x‖y‖z, 12 limbs each, at index d − 1.
    : ( Vec i ) jac ( _magn 180 )
    : P256Pt p ( _p256_pt_mag )
    ( __p256_copy_d . p x qx ) ( __p256_copy_d . p y qy ) ( __p256_copy_d . p z one_m )
    ( _p256_tbl_put jac 0 p )
    ( _p256_jdbl_d scr p )
    ( _p256_tbl_put jac 1 p )
    : ~ i d 3
    ~ < d 16 {
        ( _p256_jmadd_d scr p qx qy one_m 0 )
        ( _p256_tbl_put jac - d 1 p )
        = d + d 1
    }
    : ( Vec i ) tbl ( _magn 128 )
    : *i tp ( vec_data [i] tbl )
    : ~ i k 0
    ~ < k 8 { = . tp k 0 = k + k 1 }
    ( _p256_batch_affine scr jac 15 tbl 1 one_m )
    ^ tbl
}

// The scalar as 32 big-endian bytes, reduced mod n in constant time. A
// shorter scalar is left-padded; a longer one is folded in byte by byte
// (Horner) — its length is public, so branching on it leaks nothing.
@ __p256_scalar_mod_n ( Vec u ) k → ( Vec u ) {
    : i len ( vec_len [u] k )
    : i head ? < len 32 len 32
    : ( Vec u ) k32 ( vec_zeroed [u] - 32 head )
    ( bytes_extend_bytes k32 ( bytes_slice k 0 head ) )
    : ~ ( Vec u ) acc ( p256n_reduce_be k32 )
    : ( Vec u ) b256 ( vec_zeroed [u] 32 )
    ( vec_put [u] b256 30 # u 1 )
    : ~ i at head
    ~ < at len {
        : ( Vec u ) one ( vec_zeroed [u] 32 )
        ( vec_put [u] one 31 ?? ( vec_get [u] k at ) { T b → b F _ → # u 0 } )
        = acc ( p256n_addmod_be ( p256n_mulmod_be acc b256 ) one )
        = at + at 1
    }
    ^ acc
}

// Scalar × affine point → affine (x, y) as 64 big-endian bytes X‖Y, the
// all-zero encoding for the identity (a scalar ≡ 0 mod n). `kbytes` is
// the scalar, big-endian, any length; bx/by are the point's affine
// coordinates as plain (non-Montgomery) limbs and must be a point of the
// curve — callers validate first (_p256_on_curve). Constant-time in the
// scalar, and complete for every scalar; see the section header. A
// coordinate that is not four limbs gives an empty Vec.
@ p256ct_scalarmult ( Vec u ) kbytes ( Vec i ) bx ( Vec i ) by → ( Vec u ) {
    ? | != ( vec_len [i] bx ) 4 != ( vec_len [i] by ) 4 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) k ( __p256_scalar_mod_n kbytes )
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) onem ( _p256_one_mont_s scr )
    : ( Vec i ) qx ( _p256_to_mont_s scr bx )
    : ( Vec i ) qy ( _p256_to_mont_s scr by )
    : ( Vec i ) tbl ( _p256_affine_multiples scr qx qy onem )
    : P256Pt acc ( _p256_pt_mag )
    ( _p256_set_identity_d scr acc )
    : ( Vec i ) ex ( _mag4 )
    : ( Vec i ) ey ( _mag4 )
    // MSB-first nibbles: window 0 is byte 0's high nibble.
    : ~ i w 0
    ~ < w 64 {
        ( _p256_jdbl_d scr acc )
        ( _p256_jdbl_d scr acc )
        ( _p256_jdbl_d scr acc )
        ( _p256_jdbl_d scr acc )
        : i bv ?? ( vec_get [u] k / w 2 ) { T b → # i b F _ → 0 }
        // `w` is public: choosing the nibble by its parity leaks nothing.
        : i digit ? == % w 2 0 & 15 >> bv 4 & 15 bv
        // keep-mask: −1 exactly when the digit is 0 (branch-free).
        : i keep - # i >> # u64 | digit - 0 digit 63 1
        ( _p256_atbl_get_d ex ey tbl digit )
        ( _p256_jmadd_d scr acc ex ey onem keep )
        = w + w 1
    }
    // Jacobian → affine: x = X/Z², y = Y/Z³ (Z = 0 → zinv = 0 → all-zero).
    : ( Vec i ) zinv ( _mag4 )
    ( _p256_inv_d scr zinv . acc z )
    ( _p256_sqr_d scr . acc z zinv )
    ( _p256_mul_d scr . acc x . acc x . acc z )
    ( _p256_mul_d scr . acc z . acc z zinv )
    ( _p256_mul_d scr . acc y . acc y . acc z )
    ( _p256_from_mont_d scr . acc x . acc x )
    ( _p256_from_mont_d scr . acc y . acc y )
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( _p256_limbs_to_be out . acc x )
    ( _p256_limbs_to_be out . acc y )
    ^ out
}

// ── fixed-base comb for the generator G (ECDSA k·G, ECDH keygen) ──────
// k·G with a SECRET k (an RFC 6979 nonce, an ephemeral ECDH key) and a
// FIXED base: everything that depends on G alone is computed once per
// process. The scalar, reduced mod n, is Booth-recoded into 52 signed
// 5-bit digits d_w ∈ [−16, 16] with k = Σ d_w·32^w, and window w has an
// affine table of its own, 1·32^w·G … 16·32^w·G. Then
//
//     k·G = Σ_w d_w·(32^w·G)
//
// is 52 mixed additions of a table entry, negated in constant time for a
// negative digit, and NO doublings: 52 × (8M+3S) against the 32 × (3M+5S)
// + 64 × (8M+3S) of the eight-tooth comb this replaces — 40 % fewer field
// operations. Each window is one constant-time scan of 16 entries, as
// before, and there are 52 scans instead of 64.
//
// Complete for every scalar, by construction. The mixed addition cannot
// add a point to itself; it handles acc = ∞ (the inf mask), digit 0 (the
// keep mask) and acc = −entry (it yields Z = 0, the right answer) — see
// the Jacobian-layer header above. Before window w the
// accumulator is L·G with L = Σ_{v<w} d_v·32^v, so acc = entry needs
// L ≡ d_w·32^w (mod n) with d_w ≠ 0:
//
//   * As integers L ≠ d_w·32^w: their difference is a signed-digit
//     expansion whose lowest non-zero digit has magnitude at most 16, so
//     it is not 0 mod 32 and the difference is not 0.
//   * For w ≤ 50, |L − d_w·32^w| < 17·32^w ≤ 17·2^250 < n, so it is not a
//     non-zero multiple of n either.
//   * The top window holds bits 254‥259 of k < n < 2^256, so d_51 ∈ {0, 1,
//     2} and L = k − d_51·2^255. L − d_51·2^255 = k − d_51·2^256 would have
//     to be −n (d_51 = 1: k = 2^256 − n) or −2n (d_51 = 2: k = 2^257 − 2n).
//     Both are below 2^226, where d_51 = 0. Contradiction.
//
// The reduction mod n is what keeps the top digit that small; the comb
// before this one skipped it and accepted a ~2⁻²²⁴ chance of the doubling
// case per addition.
//
// The 832 affine entries (53 KB) are built on first use from G alone —
// no constant blob to audit — with public-point arithmetic and one batch
// inversion, and shared through publish-once slot 5.

// G's affine coordinates, plain little-endian limbs.
@ _p256_gx_plain → ( Vec i ) {
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0xF4A13945D898C296 = . q 1 # i 0x77037D812DEB33A0
    = . q 2 # i 0xF8BCE6E563A440F2 = . q 3 # i 0x6B17D1F2E12C4247
    ^ v
}

@ _p256_gy_plain → ( Vec i ) {
    : ( Vec i ) v ( _mag4 )
    : *i q ( vec_data [i] v )
    = . q 0 # i 0xCBB6406837BF51F5 = . q 1 # i 0x2BCE33576B315ECE
    = . q 2 # i 0x8EE7EB4A7C0F9E16 = . q 3 # i 0x4FE342E2FE1A7F9B
    ^ v
}

// 32 big-endian bytes at offset `off` → four little-endian 2^64 limbs.
@ _p256_be32_to_limbs ( Vec u ) src i off → ( Vec i ) {
    : ( Vec i ) out ( vec_with_cap [i] 4 )
    : ~ i k 0
    ~ < k 4 {
        // limb k = bytes [off + 24−8k … off + 31−8k], big-endian.
        : i base + off - 24 * 8 k
        : ~ u64 acc 0
        : ~ i j 0
        ~ < j 8 {
            : u64 bj # u64 ?? ( vec_get [u] src + base j ) { T b → # i b F _ → 0 }
            = acc | << acc 8 bj
            = j + j 1
        }
        ( vec_push [i] out # i acc )
        = k + k 1
    }
    ^ out
}

// The comb table: window w's entries j·32^w·G (j = 1‥16) at slots
// 16·w + j − 1, x‖y Montgomery affine. Every point is public. Within a
// window the even multiples are doublings of the half (2B, 4B = 2·2B, …,
// 16B = 2·8B) and the odd ones (j−1)·B + B with 3 ≤ j ≤ 15 — never ±B, so
// the plain Jacobian addition is exact — and the next window's base is
// 32·B = 2·(16·B).
@ __p256_comb_build → ( Vec i ) {
    : P256Scratch scr ( _p256_scr_new )
    : ( Vec i ) onem ( _p256_one_mont_s scr )
    : ( Vec i ) gx ( _p256_to_mont_s scr ( _p256_gx_plain ) )
    : ( Vec i ) gy ( _p256_to_mont_s scr ( _p256_gy_plain ) )
    : ( Vec i ) jac ( _magn * 832 12 )
    : P256Pt b ( _p256_pt_mag )
    : P256Pt p ( _p256_pt_mag )
    ( __p256_copy_d . b x gx ) ( __p256_copy_d . b y gy ) ( __p256_copy_d . b z onem )
    : ~ i w 0
    ~ < w 52 {
        : i base * w 16
        ( _p256_tbl_put jac base b )
        : ~ i j 2
        ~ <= j 16 {
            ? == % j 2 0 {
                ( _p256_tbl_get p jac - + base / j 2 1 )
                ( _p256_jdbl_d scr p )
            } {
                ( _p256_tbl_get p jac - + base j 2 )
                ( _p256_jadd_d scr p b )
            }
            ( _p256_tbl_put jac - + base j 1 p )
            = j + j 1
        }
        // p holds 16·B
        ( _p256_jdbl_d scr p )
        ( __p256_pt_copy_d b p )
        = w + w 1
    }
    : ( Vec i ) tbl ( _magn * 832 8 )
    ( _p256_batch_affine scr jac 832 tbl 0 onem )
    ^ tbl
}

: ~ i g_p256_comb_tbl 0

// The comb table, built by the first caller; two first callers may both
// build, publish-once slot 5 keeps one (registry: stdlib/std/tls_server.nu)
// and the other copy is dropped. The winner lives for the rest of the
// program, through the global — callers BORROW it and must not free it.
@ __p256_comb_tbl → ( Vec i ) {
    ? == g_p256_comb_tbl 0 {
        : ( Vec i ) tbl ( __p256_comb_build )
        = g_p256_comb_tbl ( vec_publish_once [i] 5 tbl )
    } {}
    ^ @ ( Vec i ) { # s g_p256_comb_tbl }
}

// The six-bit Booth window w of a scalar held as five little-endian limbs
// (the fifth 0): bits 5w−1 … 5w+4, bit −1 being 0. `w` is public, so
// choosing limbs and shifts by it leaks nothing.
@ __p256_booth_bits * i kl i w → i {
    ? == w 0 { ^ & << . kl 0 1 63 } {}
    : i lo - * 5 w 1
    : i q / lo 64
    : i r % lo 64
    : u64 v >> # u64 . kl q r
    : u64 hi ? > r 58 << # u64 . kl + q 1 - 64 r 0
    ^ # i & | v hi 63
}

// Constant-time read of window w's entry `digit` (1‥16; 0 reads all
// zero) into (ex, ey). `digit` comes from the secret scalar: every one of
// the sixteen entries is read, every time, and merged under a mask that
// is all-ones exactly on the match — arithmetic, not a comparison (see
// _p256_atbl_get_d). The address stream depends on w alone.
@ __p256_comb_get_d ( Vec i ) ex ( Vec i ) ey ( Vec i ) tbl i w i digit → v {
    : *i tp # *i + # i ( vec_data [i] tbl ) * * w 128 8
    : ~ i x0 0
    : ~ i x1 0
    : ~ i x2 0
    : ~ i x3 0
    : ~ i y0 0
    : ~ i y1 0
    : ~ i y2 0
    : ~ i y3 0
    : ~ i s 0
    ~ < s 16 {
        : u64 z ^^ # u64 + s 1 # u64 digit
        : i mask - 0 # i >> - z 1 63
        : i b * s 8
        = x0 | x0 & mask . tp b
        = x1 | x1 & mask . tp + b 1
        = x2 | x2 & mask . tp + b 2
        = x3 | x3 & mask . tp + b 3
        = y0 | y0 & mask . tp + b 4
        = y1 | y1 & mask . tp + b 5
        = y2 | y2 & mask . tp + b 6
        = y3 | y3 & mask . tp + b 7
        = s + s 1
    }
    : *i xp ( vec_data [i] ex )
    : *i yp ( vec_data [i] ey )
    = . xp 0 x0 = . xp 1 x1 = . xp 2 x2 = . xp 3 x3
    = . yp 0 y0 = . yp 1 y1 = . yp 2 y2 = . yp 3 y3
}

// scalar · G → 64 bytes X‖Y (all zero for a scalar ≡ 0 mod n), constant
// time in the scalar: 52 windows, each one Booth recode, one masked
// table scan, one masked negation and one masked mixed addition.
@ p256ct_scalarmult_base ( Vec u ) kbytes → ( Vec u ) {
    : ( Vec u ) k ( __p256_scalar_mod_n kbytes )
    : ( Vec i ) kl4 ( _p256_be32_to_limbs k 0 )
    : ( Vec i ) kl ( _magn 5 )
    : *i kp ( vec_data [i] kl )
    ( __p256_copy_d kl kl4 )
    = . kp 4 0
    : P256Scratch scr ( _p256_scr_new )
    // Shared, lazily-built table of G multiples — BORROWED from the
    // global cache; must not be freed here.
    : ( Vec i ) tbl ( __p256_comb_tbl )
    : ( Vec i ) onem ( _p256_one_mont_s scr )
    : ( Vec i ) zero ( __zeros4 )
    : ( Vec i ) ex ( _mag4 )
    : ( Vec i ) ey ( _mag4 )
    : ( Vec i ) ny ( _mag4 )
    // acc = ∞: Z = 0 (X/Y are irrelevant while Z = 0; the first committed
    // addition replaces all three coordinates through the ∞ mask).
    : P256Pt acc ( _p256_pt_mag )
    ( _p256_set_identity_d scr acc )
    : ~ i w 0
    ~ < w 52 {
        // Booth recode (constant time): the six-bit window b5‥b0 is the
        // digit b0 + b1 + 2b2 + 4b3 + 8b4 − 16b5. neg is all-ones when b5
        // is set, and the magnitude is then that of the complement,
        // 63 − in, halved and rounded up.
        : i inb ( __p256_booth_bits kp w )
        : i neg - 0 >> inb 5
        : i dd | & - 63 inb neg & inb ^^ neg - 0 1
        : i digit + >> dd 1 & dd 1
        // keep-mask: −1 exactly when the digit is 0 (branch-free).
        : i keep - # i >> # u64 | digit - 0 digit 63 1
        ( __p256_comb_get_d ex ey tbl w digit )
        ( __p256_sub_d scr ny zero ey )
        ( __p256_lmerge_d ey neg ^^ neg - 0 1 ny ey )
        ( _p256_jmadd_d scr acc ex ey onem keep )
        = w + w 1
    }
    // Jacobian → affine: x = X/Z², y = Y/Z³ (Z = 0 → zinv = 0 → the
    // all-zero identity output).
    : ( Vec i ) zinv ( _mag4 )
    ( _p256_inv_d scr zinv . acc z )
    ( _p256_sqr_d scr . acc z zinv )
    ( _p256_mul_d scr . acc x . acc x . acc z )
    ( _p256_mul_d scr . acc z . acc z zinv )
    ( _p256_mul_d scr . acc y . acc y . acc z )
    ( _p256_from_mont_d scr . acc x . acc x )
    ( _p256_from_mont_d scr . acc y . acc y )
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    ( _p256_limbs_to_be out . acc x )
    ( _p256_limbs_to_be out . acc y )
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
