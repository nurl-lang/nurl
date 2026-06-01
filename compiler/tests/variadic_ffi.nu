// Test: variadic FFI + automatic argument promotion (grammar v1.9).
//
// Shipped 2026-05-14 as the natural follow-on to Phase 1A/1B fixed-
// size types. Covers calling printf with mixed
// integer/float widths no longer needs hand-rolled widening at every
// call site.
//
// Coverage:
//   * `...` lexer token (LTT_ELLIPSIS = 43, runtime.c)
//   * gen_ffi_decl: records `<fname>__variadic` + `__variadic_fixed`
//   * gen_call: variadic_promote_arg + variadic_promoted_type on args
//     whose 0-based index >= fixed count
//   * float → double via fpext
//   * i1 / i8 / i16 → i32 via sext (signed) or zext (unsigned, from
//     `__last_unsigned__` side-channel that gen_ident propagates from
//     the binding's `__unsigned` flag)
//   * i32 / i64 / i8* pass through unchanged (no IR pollution)
//
// printf's declared return type is i32 to match the prelude's
// `declare i32 @printf(i8*, ...)` — using `→ i` (i64) would emit a
// `call i64` that mismatches the prelude declare.

& `libc` @ printf s fmt ... → i32

@ main → i {
    // ── Fixed-width args of every category ─────────────────────────
    : i32 a 42
    : u32 b 12345
    : f32 c # f32 3.5
    : i d 9000000000  // plain `i` = i64
    : s e `hello`

    ( printf `i32=%d u32=%u f32=%g i64=%lld s=%s\n` a b c d e )

    // ── Bool promotion (i1 → i32 via zext) ─────────────────────────
    ( printf `bool=%d\n` T )

    // ── Narrow signed promotion (i8 → i32 via sext) ────────────────
    : i8 sm # i8 -7
    ( printf `i8=%d\n` sm )

    // ── Narrow unsigned byte promotion (u/i8 → i32 via zext) ───────
    //    Without zext, 200 would sign-extend to -56.
    : u um # u 200
    ( printf `u=%d\n` um )

    // ── 16-bit signed + unsigned in the same call ──────────────────
    : i16 sh16 # i16 -3000
    : u16 uh16 # u16 60000
    ( printf `i16=%d u16=%d\n` sh16 uh16 )

    // ── Pure-i64 args (pass through unchanged) ─────────────────────
    : i big 1234567890123
    ( printf `i64=%lld\n` big )

    // ── Float-arithmetic result promoted at the call site ──────────
    : f32 fx # f32 1.25
    : f32 fy # f32 2.5
    ( printf `f32_sum=%g\n` + fx fy )

    ^ 0
}
