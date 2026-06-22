// const_ternary_signedness.nu — regression for two silent miscompiles
// found by hand-probing while extending the differential fuzzer
// (tools/fuzz) on 2026-06-02.
//
// Same root cause as the rest of the signedness family — the LLVM integer
// type can't carry NURL's u-vs-signed distinction, so it rides the
// `__last_unsigned__` side-channel, and these two value-producing sites
// forgot to set it:
//   * An unsigned-typed GLOBAL CONST load (`# i GU` over `: u GU 200`)
//     widened with sext → −56 instead of 200. gen_const_decl now records
//     `<const>__unsigned`, which gen_ident already propagates.
//   * A `?` (ternary) result whose arms are unsigned (`# i ? c (# u 200)
//     (# u 100)`) widened with sext. gen_cond now snapshots each arm's
//     signedness and sets the result flag.
//
// main returns the number of failed checks (0 = all pass).

: u GU 200
: u16 GW 50000
: u32 GD 2147483649
: i8 GS 200  // signed const, must stay sext

@ chk i got i want s tag → i {
    ? == got want {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ main → i {
    : ~ i f 0
    // Unsigned global consts → zext.
    = f + f ( chk # i64 # i GU 200 `const_u8_zext` )
    = f + f ( chk # i64 # i GW 50000 `const_u16_zext` )
    = f + f ( chk # i64 # i GD 2147483649 `const_u32_zext` )
    // Signed global const → sext (200 as i8 = −56).
    = f + f ( chk # i64 # i64 GS - 0 56 `const_i8_sext` )
    // Ternary whose arms are unsigned → zext the selected value.
    = f + f ( chk # i64 # i ? > 1 0 # u 200 # u 100 200 `tern_u8_zext` )
    = f + f ( chk # i64 # i ? > 0 1 # u16 1 GW 50000 `tern_u16_zext` )
    // Ternary whose arms are signed → sext.
    = f + f ( chk # i64 # i64 ? > 1 0 # i8 200 # i8 5 - 0 56 `tern_i8_sext` )
    ^ f
}
