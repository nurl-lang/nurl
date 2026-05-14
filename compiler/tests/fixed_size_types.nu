// Test: fixed-size integer and float types (grammar v1.8).
//
// Phase 1A — shipped 2026-05-14:
//   * Lexer: multi-char TYPE_KW recognises i8/i16/i32/u16/u32/u64/f32
//   * llvm_type / sizeof_nurl / llvm_to_nurl: new mappings
//   * Per-binding `__nurl_type` + `__unsigned` side-channel
//   * coerce_store_val: trunc/sext/zext for int-width adjustment
//   * gen_cast: sext (signed source) vs zext (unsigned), fpext/fptrunc
//     for float ↔ double, fptosi/sitofp covering both float widths
//   * binop_instr: `isf` recognises both `double` and `float`
//
// Phase 1B (later): unsigned arithmetic (udiv/urem/lshr/icmp u*) for
// u16/u32/u64 still emits signed ops in v1.8. `u` (i8) keeps its
// historical unsigned semantics via the existing `seq lt "i8"` test
// in gen_binary. Sized-unsigned arithmetic is signed for now — known
// limitation, documented in spec/grammar.ebnf v1.8 §6.

@ main → i {
    // ── Basic declarations: every width parses + stores its literal ──
    : i8 a 127
    : i16 b 30000
    : i32 c 2000000000
    : u16 d 65000
    : u32 e 4000000000
    : u64 f 100000000000

    // Widen each back to `i` for printing. Signed widening uses sext,
    // unsigned uses zext — bits 0xC0…000000 in c (negative if treated
    // as signed i32) stays negative when widened from signed i32, but
    // an unsigned u32 of the same bit pattern widens positively.
    ( nurl_print `a=` ) ( nurl_print ( nurl_str_int # i a ) ) ( nurl_print `\n` )
    ( nurl_print `b=` ) ( nurl_print ( nurl_str_int # i b ) ) ( nurl_print `\n` )
    ( nurl_print `c=` ) ( nurl_print ( nurl_str_int # i c ) ) ( nurl_print `\n` )
    ( nurl_print `d=` ) ( nurl_print ( nurl_str_int # i d ) ) ( nurl_print `\n` )
    ( nurl_print `e=` ) ( nurl_print ( nurl_str_int # i e ) ) ( nurl_print `\n` )
    ( nurl_print `f=` ) ( nurl_print ( nurl_str_int # i f ) ) ( nurl_print `\n` )

    // ── Sign-preserving widening of negative i32 ─────────────────────
    // Was the original failure mode: zext-of-i32(-1000) gave 4294966296.
    : i big - 0 1000
    : i32 nsig # i32 big
    : i back # i nsig
    ( nurl_print `nsig back=` )
    ( nurl_print ( nurl_str_int back ) ) ( nurl_print `\n` )

    // ── Unsigned widening: zext keeps the high bits clear ────────────
    : i raw 4000000000  // > 2^31, fits in u32 but not i32
    : u32 unsig # u32 raw
    : i ubacked # i unsig
    ( nurl_print `unsig back=` )
    ( nurl_print ( nurl_str_int ubacked ) ) ( nurl_print `\n` )

    // ── Narrowing (trunc) ────────────────────────────────────────────
    // NURL doesn't lex hex literals — decimal 305419896 is 0x12345678.
    // Low 16 bits = 0x5678 = 22136, fits in signed i16. sext on read-back.
    : i32 wide 305419896
    : i16 narrow # i16 wide
    : i nb # i narrow
    ( nurl_print `narrow=` )
    ( nurl_print ( nurl_str_int nb ) ) ( nurl_print `\n` )

    // ── Float widths: f32 arithmetic + f ↔ f32 conversions ───────────
    : f32 fx # f32 1.5
    : f32 fy # f32 2.25
    : f32 fz + fx fy
    : f dz # f fz  // fpext float → double
    : f32 ftrunc # f32 dz  // fptrunc double → float
    ( nurl_print `fz≈3.75: ` )
    ( nurl_print ( nurl_str_float dz ) ) ( nurl_print `\n` )
    : f back_d # f ftrunc
    ( nurl_print `roundtrip≈3.75: ` )
    ( nurl_print ( nurl_str_float back_d ) ) ( nurl_print `\n` )

    // ── sizeof Z ─────────────────────────────────────────────────────
    ( nurl_print `Zi8=` ) ( nurl_print ( nurl_str_int Z i8 ) ) ( nurl_print `\n` )
    ( nurl_print `Zi16=` ) ( nurl_print ( nurl_str_int Z i16 ) ) ( nurl_print `\n` )
    ( nurl_print `Zi32=` ) ( nurl_print ( nurl_str_int Z i32 ) ) ( nurl_print `\n` )
    ( nurl_print `Zu64=` ) ( nurl_print ( nurl_str_int Z u64 ) ) ( nurl_print `\n` )
    ( nurl_print `Zf32=` ) ( nurl_print ( nurl_str_int Z f32 ) ) ( nurl_print `\n` )

    ^ 0
}
