// struct_field_signedness.nu — regression for a silent struct-field-load
// miscompile found by hand-probing while extending the differential fuzzer
// (tools/fuzz) on 2026-06-02.
//
// Bug: loading an UNSIGNED sized-int struct field and widening it
// (`# i . rec u8field`) sign-extended instead of zero-extending — a u8
// field holding 200 read back as −56, a u16 50000 as a negative, a u32
// 0x80000001 as negative. Same root cause as the earlier casts: the LLVM
// field type (i8/i16/i32) can't carry NURL's signedness, and `gen_member`
// never surfaced the field's declared `u`/`u16`/`u32`-ness onto the
// `__last_unsigned__` side-channel the enclosing widening cast consults.
// `gen_struct_decl` now records `<S>__<field>__unsigned`; both the value
// (extractvalue) and pointer (GEP+load) field-load paths set it.
//
// main returns the number of failed checks (0 = all pass).

: Rec {
    u b0  // unsigned byte
    i8 s0  // signed byte
    u16 w0  // unsigned 16
    i16 h0  // signed 16
    u32 d0  // unsigned 32
}

// Wider fields fed NARROWER unsigned values — the construction store must
// zero-extend (a `u` 130 into an i64 field is 130, not −126), the mirror of
// the field-LOAD bug, fixed in gen_agg_lit.
: Wide {
    i64 a  // fed u8 130
    i32 b  // fed u16 50000
    i64 c  // fed u32 0x80000001
}

@ chk i got i want s tag → i {
    ? == got want {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ main → i {
    : Rec r @ Rec { # u 200 # i8 200 # u16 50000 # i16 50000 # u32 2147483649 }
    : ~ i f 0
    // Unsigned fields → zero-extend.
    = f + f ( chk # i64 # i . r b0 200 `u8_field_zext` )
    = f + f ( chk # i64 # i . r w0 50000 `u16_field_zext` )
    = f + f ( chk # i64 # i . r d0 2147483649 `u32_field_zext` )
    // Signed fields → sign-extend (i16 50000 wraps to −15536).
    = f + f ( chk # i64 # i64 . r s0 - 0 56 `i8_field_sext` )
    = f + f ( chk # i64 # i64 . r h0 - 0 15536 `i16_field_sext` )
    // Construction store coercion: narrower unsigned value into wider field.
    : Wide w @ Wide { # u 130 # u16 50000 # u32 2147483649 }
    = f + f ( chk # i64 . w a 130 `u8_into_i64_field` )
    = f + f ( chk # i64 # i64 . w b 50000 `u16_into_i32_field` )
    = f + f ( chk # i64 . w c 2147483649 `u32_into_i64_field` )
    ^ f
}
