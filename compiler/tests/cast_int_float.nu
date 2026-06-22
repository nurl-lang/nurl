// cast_int_float.nu — regression for a silent int↔float conversion
// miscompile found by extending the differential fuzzer's probes
// (tools/fuzz) on 2026-06-02.
//
// Bug: `# f # u32 X` lowered an UNSIGNED int → float with `sitofp`, so an
// unsigned value with the high bit set converted to a NEGATIVE float
// (`# f # u32 0x80000001` ≈ −2.1e9 instead of +2.1e9; `# f # u 200` ≈ −56
// instead of 200). Same root cause as the i8/`u` ambiguity: the LLVM
// integer type can't carry signedness, so the conversion must consult the
// `__last_unsigned__` side-channel. `gen_cast` now picks uitofp/sitofp
// (int→float) and fptoui/fptosi (float→int) from the source/target
// signedness.
//
// Checks use exact int→float→int ROUND-TRIPS (`# i64 # f # T v`): every
// value here fits the mantissa (|v| < 2^24 for f32, < 2^32 for f64), so
// the round-trip is exact and the expected i64 is the true integer value.
// main returns the number of failed checks (0 = all pass).

@ chk i got i want s tag → i {
    ? == got want {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ main → i {
    : ~ i f 0
    // Unsigned source → uitofp (high-bit-set values stay positive).
    = f + f ( chk # i64 # f # u32 2147483649 2147483649 `u32_to_f` )  // 0x80000001
    = f + f ( chk # i64 # f # u 200 200 `u8_to_f` )  // 0xC8
    = f + f ( chk # i64 # f # u16 50000 50000 `u16_to_f` )
    // Signed source → sitofp (negatives stay negative).
    = f + f ( chk # i64 # f # i32 - 0 5 - 0 5 `i32_to_f` )
    = f + f ( chk # i64 # f # i8 - 0 100 - 0 100 `i8_to_f` )
    // f32 path (exact for |v| < 2^24).
    = f + f ( chk # i64 # f32 # u16 50000 50000 `u16_to_f32` )
    = f + f ( chk # i64 # f32 # i16 - 0 9000 - 0 9000 `i16_to_f32` )
    = f + f ( chk # i64 # f # u 255 255 `u8_max_to_f` )
    // A float result must NOT leave a stale `__last_unsigned__` from its
    // int source: here FloatRT(# u 5) set the unsigned flag, and without
    // clearing it the negative product −65 was divided with udiv (garbage)
    // instead of sdiv. −13 * 5 = −65; −65 / 7 = −9.
    = f + f ( chk # i64 / * # i64 # f # i8 - 0 13 # i64 # f # u 5 # i64 7 - 0 9 `floatrt_div_sdiv` )
    ^ f
}
