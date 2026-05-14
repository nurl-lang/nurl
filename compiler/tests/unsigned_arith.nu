// Test: unsigned arithmetic for sized u-types (Phase 1B of fixed-size types).
//
// Phase 1A shipped fixed-size type DECLARATIONS + cast/store width
// adjustment. Phase 1B (this) makes `gen_binary` pick the unsigned
// LLVM op family (`udiv` / `urem` / `lshr` / `icmp u*`) when an
// operand is declared as a sized unsigned type (`u16` / `u32` / `u64`),
// matching the legacy 8-bit `u` behaviour.
//
// Implementation: `gen_ident` now stores the binding's `__unsigned`
// flag into a side-channel `__last_unsigned__` symbol. `gen_binary`
// snapshots the LHS marker before evaluating the RHS, and selects
// the unsigned op family if either operand carries the flag.
// `gen_binary` also propagates the result's signedness for nested
// expressions like `+ a + b c`.
//
// Bitwise `&` / `|` are sign-agnostic LLVM ops, so they take the
// same path — but the i64/i32-only gate in
// `gen_logical_or_bitwise_and` / `_or` was broadened to all integer
// widths so `i8` / `i16` / `u16` operands now compose with `&` and
// `|` without an explicit cast.

@ main → i {
  // ── udiv vs sdiv: high-bit-set u32 ───────────────────────────────
  // 3000000000 / 1000:
  //   udiv → 3000000 (correct for unsigned)
  //   sdiv → -1294967 (3000000000 wraps to -1294967296 when read as i32)
  : u32 huge_u 3000000000
  : u32 d_u 1000
  : u32 q_u / huge_u d_u
  ( nurl_print `udiv=` )
  ( nurl_print ( nurl_str_int # i q_u ) )
  ( nurl_print `\n` )

  // ── urem vs srem ─────────────────────────────────────────────────
  : u32 r_u % huge_u d_u
  ( nurl_print `urem=` )
  ( nurl_print ( nurl_str_int # i r_u ) )
  ( nurl_print `\n` )

  // ── lshr vs ashr: right-shift 3000000000 by 16 ───────────────────
  //   lshr → 45776  (3000000000 / 65536, rounded down)
  //   ashr → would smear sign-bit if read as i32: 65535-tailored
  : u32 shifted >> huge_u 16
  ( nurl_print `lshr=` )
  ( nurl_print ( nurl_str_int # i shifted ) )
  ( nurl_print `\n` )

  // ── icmp ult vs slt: same bit pattern, two interpretations ───────
  : u32 a_u 3000000000
  : u32 b_u 4000000000
  ( nurl_print `ult(3B,4B)=` )
  ( nurl_print ? < a_u b_u `T\n` `F\n` )

  // Sanity: signed i32 of the same bit pattern reads as negative.
  : i32 a_s # i32 a_u
  ( nurl_print `slt(=as-i32, 0)=` )
  ( nurl_print ? < a_s 0 `T\n` `F\n` )

  // ── u16 path: udiv on high-bit-set u16 ───────────────────────────
  // 50000 / 100:
  //   udiv → 500
  //   sdiv would interpret 50000 as -15536 (i16): -15536 / 100 = -155
  : u16 huge16 50000
  : u16 d16 100
  : u16 q16 / huge16 d16
  ( nurl_print `u16 udiv=` )
  ( nurl_print ( nurl_str_int # i q16 ) )
  ( nurl_print `\n` )

  // ── u64 path: udiv on huge u64 ───────────────────────────────────
  : u64 big64 12000000000
  : u64 d64 7
  : u64 q64 / big64 d64
  ( nurl_print `u64 udiv=` )
  ( nurl_print ( nurl_str_int # i q64 ) )
  ( nurl_print `\n` )

  // ── Bitwise & / | on i16 (was rejected by the i64/i32-only gate) ─
  : i16 x16 240
  : i16 y16 15
  : i16 and16 & x16 y16
  : i16 or16  | x16 y16
  ( nurl_print `i16 and=` )
  ( nurl_print ( nurl_str_int # i and16 ) )
  ( nurl_print `\n` )
  ( nurl_print `i16 or=` )
  ( nurl_print ( nurl_str_int # i or16 ) )
  ( nurl_print `\n` )

  // ── Nested expression: result of inner + carries unsigned flag ───
  // (+ a (+ b c)) where a, b, c are u32. The outer + sees an
  // unsigned LHS (from the inner +), so a downstream / divides the
  // sum unsigned-correctly.
  : u32 sum + a_u + b_u 1000000
  // sum = 3000000000 + 4001000000 = 7001000000 (overflows u32 with
  // wraparound to ~2706032704). Divide by 2: unsigned division.
  : u32 half / sum 2
  ( nurl_print `nested half=` )
  ( nurl_print ( nurl_str_int # i half ) )
  ( nurl_print `\n` )

  ^ 0
}
