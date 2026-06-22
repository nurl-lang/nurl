// fn_return_signedness.nu — regression for a silent miscompile found by
// hand-probing while extending the differential fuzzer (tools/fuzz) on
// 2026-06-02.
//
// Bug: a call to a function whose return type is an unsigned sized int
// (`u`/`u16`/`u32`), with the result immediately widened (`# i ( f )`),
// sign-extended — `# i ( ret_u )` over a `→ u` returning 200 gave −56. The
// call site never carried the callee's return signedness onto the
// `__last_unsigned__` side-channel the enclosing widening cast consults
// (the LLVM return type i8/i16/i32 can't distinguish `u` from `i8`).
// scan_fn_sigs now records `<fn>__ret_unsigned`; gen_call re-asserts it on
// `__last_unsigned__` after the call.
//
// main returns the number of failed checks (0 = all pass).

@ ret_u → u { ^ # u 200 }

@ ret_i8 → i8 { ^ # i8 200 }

@ ret_u16 → u16 { ^ # u16 50000 }

@ ret_u32 → u32 { ^ # u32 2147483649 }

@ add_u u a u b → u { ^ + a b }  // unsigned return computed from params

@ chk i got i want s tag → i {
    ? == got want {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ main → i {
    : ~ i f 0
    = f + f ( chk # i64 # i ( ret_u ) 200 `ret_u_zext` )
    = f + f ( chk # i64 # i64 ( ret_i8 ) - 0 56 `ret_i8_sext` )
    = f + f ( chk # i64 # i ( ret_u16 ) 50000 `ret_u16_zext` )
    = f + f ( chk # i64 # i ( ret_u32 ) 2147483649 `ret_u32_zext` )
    // Unsigned return widened correctly even with args + wrapping: 200+100
    // wraps in u8 to 44, then zero-extends to 44 (not a negative).
    = f + f ( chk # i64 # i ( add_u # u 200 # u 100 ) 44 `add_u_zext` )
    ^ f
}
