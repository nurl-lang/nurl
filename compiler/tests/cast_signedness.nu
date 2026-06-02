// cast_signedness.nu — regression for two silent integer miscompiles
// found by the differential fuzzer (tools/fuzz) on 2026-06-02.
//
// Bug 1 — unsigned-byte cast widening: `# i64 # u 217` sign-extended a
//   `u` (unsigned byte) instead of zero-extending, because a nested
//   cast-to-unsigned never set the `__last_unsigned__` side-channel that
//   the enclosing widening cast consults. (Only casts whose subject was a
//   typed BINDING widened correctly.)
//
// Bug 2 — signed `i8` mis-classified as unsigned: gen_binary inferred
//   "unsigned" from the LLVM type `i8`, but BOTH the unsigned NURL `u` and
//   the SIGNED `i8` lower to LLVM i8. So signed i8 arithmetic selected
//   udiv/urem/lshr/icmp-u and marked its result unsigned (silently
//   zero-extending a negative value at the next widen).
//
// main returns the number of failed checks (0 = all pass), so any
// regression trips the suite's exit-code gate.

@ chk i got i want s tag → i {
    ? == got want {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ main → i {
    : ~ i f 0
    // Bug 1: unsigned widening must zero-extend.
    = f + f ( chk # i64 # u 217 217 `u8_zext` )
    = f + f ( chk # i64 # u16 50000 50000 `u16_zext` )
    = f + f ( chk # i64 # u32 2147483649 2147483649 `u32_zext` )
    // Bug 1 mirror: signed widening must still sign-extend.
    = f + f ( chk # i64 # i8 200 - 0 56 `i8_sext` )
    = f + f ( chk # i64 # i16 # i8 200 - 0 56 `i8_i16_sext` )
    // Bug 2: signed i8 arithmetic must use SIGNED ops.
    = f + f ( chk # i64 / # i8 200 # i8 7 - 0 8 `i8_sdiv` )       // -56 / 7 = -8
    = f + f ( chk # i64 >> # i8 200 # i8 1 - 0 28 `i8_ashr` )     // -56 >> 1 = -28
    = f + f ( chk # i64 ? < # i8 200 # i8 5 1 0 1 `i8_slt` )      // -56 < 5 = true
    = f + f ( chk # i64 # i16 << + # i8 80 # i8 94 # i8 5 - 0 64 `i8_shl_widen` )
    // Unsigned `u` must still use UNSIGNED ops (no regression).
    = f + f ( chk # i64 / # u 200 # u 7 28 `u8_udiv` )            // 200 / 7 = 28
    = f + f ( chk # i64 >> # u 200 # u 1 100 `u8_lshr` )          // 200 >> 1 = 100
    = f + f ( chk # i64 ? < # u 200 # u 5 1 0 0 `u8_ult` )        // 200 < 5 = false
    ^ f
}
