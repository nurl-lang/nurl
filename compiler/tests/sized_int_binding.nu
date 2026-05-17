// sized_int_binding.nu — regression for gotcha #7 (typed FFI return
// binding emits store-before-define) + the underlying lexer hole.
//
// Pre-2026-05-17 the lexer didn't recognise `i64` as a TYPE_KW (only
// `i8`/`i16`/`i32`/`u16`/`u32`/`u64`/`f32` were in the multi-char list),
// so `: i64 a 5` parsed via the inferred-type branch with `i64` as the
// binding name and `a 5` as the value. The generated IR ended up with
// `store i64 %a, i64* %r1` where `%a` was never defined.
//
// Symmetric fix in `llvm_type` added the missing `i64 → i64` mapping
// row; the chain was otherwise hitting the fallback `%i64` named-type
// path, which then triggered `alloca %i64` (unsized).
//
// This test covers explicit-type bindings for every sized integer
// (signed + unsigned), with literal RHS and FFI-call RHS, plus boundary
// values that prove the round-trip without truncation.

& `c` @ getpid → i32

@ main → i {
    // ── i64 literal ─────────────────────────────────────────────
    : i64 a 42
    ( nurl_print `i64=` ) ( nurl_print ( nurl_str_int a ) ) ( nurl_print `\n` )

    // ── i32 from FFI call (the original gotcha-7 shape) ──────────
    : i32 b ( getpid )
    : i b_wide # i b
    : b b_pos > b_wide 0
    ( nurl_print `i32_from_ffi_positive=` ) ( nurl_print ? b_pos `T` `F` ) ( nurl_print `\n` )

    // ── i16, i8 literals ─────────────────────────────────────────
    : i16 c # i16 32767
    ( nurl_print `i16_max=` ) ( nurl_print ( nurl_str_int # i c ) ) ( nurl_print `\n` )

    : i8 d # i8 127
    ( nurl_print `i8_max=` ) ( nurl_print ( nurl_str_int # i d ) ) ( nurl_print `\n` )

    // ── u16 / u32 / u64 boundary round-trips ─────────────────────
    : u16 e # u16 65535
    ( nurl_print `u16_max=` ) ( nurl_print ( nurl_str_int # i e ) ) ( nurl_print `\n` )

    : u32 f # u32 4294967295
    ( nurl_print `u32_max=` ) ( nurl_print ( nurl_str_int # i f ) ) ( nurl_print `\n` )

    // u64 max (2^64 - 1) — print as the wrap-around since nurl_str_int
    // emits signed decimal: the i64 view of 0xFFFFFFFFFFFFFFFF is -1.
    : u64 g # u64 -1
    ( nurl_print `u64_neg1=` ) ( nurl_print ( nurl_str_int # i g ) ) ( nurl_print `\n` )

    ^ 0
}
