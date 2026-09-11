// tests/ir_test.nu — wb_prepare_ir_for_wasi as a pure string rewrite:
// code symbols get retargeted, `c"…"` string-constant DATA does not.
//
// The interesting case is a program whose data contains the rewriter's
// own masking sentinel. Every program that embeds wasmbuilder does
// (swarm-mcp compiles kernels through this package), and an unmask that
// mapped the sentinel back to `@` unconditionally rewrote such a
// constant's contents without touching its `[N x i8]` length — clang
// then rejected the module with "constant expression type mismatch".

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/wasi_ir.nu`

@ __want String hay s needle s what → i {
    ? ( string_contains hay needle ) { ^ 0 } {}
    : String m ( string_from `FAIL: ` )
    ( string_push_str m what )
    ( string_push_str m ` — missing: ` )
    ( string_push_str m needle )
    ( nurl_eprintln ( string_data m ) )
    ( string_free m )
    ^ 1
}

@ __want_not String hay s needle s what → i {
    ? ( string_contains hay needle ) {} { ^ 0 }
    : String m ( string_from `FAIL: ` )
    ( string_push_str m what )
    ( string_push_str m ` — leftover: ` )
    ( string_push_str m needle )
    ( nurl_eprintln ( string_data m ) )
    ( string_free m )
    ^ 1
}

// Exercise type preservation through the public rewriter. This synthetic
// declaration probes parsing, not the platform ABI of pthread_create.
@ __test_param_types → i {
    : String line ( string_from `declare i32 @pthread_create({ i8*, i64 } byval({ i8*, i64 }), [2 x i64]* nofree, <2 x float>, void (i8*, i64)* nocapture, %"quoted type,(x)"* nocapture, i8* dereferenceable(4), ptr addrspace(1) nofree, ...) "custom"="(,)"\n` )
    : String out ( wb_prepare_ir_for_wasi line )
    ( string_free line )
    : ~ i bad ( __want out `@__nurl_pthread_create_stub({ i8*, i64 }, [2 x i64]*, <2 x float>, void (i8*, i64)*, %"quoted type,(x)"*, i8*, ptr addrspace(1))` `nested types survive; attributes and varargs do not` )
    ( string_free out )
    : String empty ( string_from `declare i32 @pthread_join() allocsize(0)\n` )
    : String empty_out ( wb_prepare_ir_for_wasi empty )
    = bad + bad ( __want empty_out `@__nurl_pthread_join_stub()` `empty parameters stop before function attributes` )
    ( string_free empty )
    ( string_free empty_out )
    ^ bad
}

@ main → i {
    : String ir ( string_new )
    // A constant holding the sentinel itself, at its true byte length.
    ( string_push_str ir `@.str.0 = private unnamed_addr constant [24 x i8] c"__NURL_IR_AT_SENTINEL__\00", align 1\n` )
    // A constant holding IR text — the case the mask exists for.
    ( string_push_str ir `@.str.1 = private unnamed_addr constant [22 x i8] c"define i32 @main(i32)\00", align 1\n` )
    // A POSIX-only symbol declared with the width the NURL source chose:
    // std/thread.nu says `→ i32`, and the stub has to say i32 too or
    // wasm-ld replaces the call with an `unreachable` trap stub.
    ( string_push_str ir `declare i32 @pthread_create(i8*, i8*, i8*, i8*)\n` )
    // Primitive ownership attributes are contracts, not LLVM value types.
    ( string_push_str ir `declare i64 @strlen(i8* nocapture nofree) readonly nofree\n` )
    ( string_push_str ir `declare i8* @memcpy(i8*, i8* nocapture nofree, i64) "nurl.value-only"="2"\n` )
    // Real code, which SHOULD be rewritten.
    ( string_push_str ir `define i32 @main(i32 %argc, i8** %argv) {\n` )
    ( string_push_str ir `  %t = call i32 @pthread_create(i8* null, i8* null, i8* null, i8* null)\n` )
    ( string_push_str ir `  ret i32 0\n` )
    ( string_push_str ir `}\n` )

    : String out ( wb_prepare_ir_for_wasi ir )
    ( string_free ir )

    : ~ i bad ( __test_param_types )
    = bad + bad ( __want out `[24 x i8] c"__NURL_IR_AT_SENTINEL__\00"` `sentinel-in-data survives byte for byte` )
    = bad + bad ( __want out `[22 x i8] c"define i32 @main(i32)\00"` `IR text in data is not retargeted` )
    = bad + bad ( __want out `define i32 @__main_argc_argv(i32 %argc, i8** %argv)` `real @main is retargeted` )
    = bad + bad ( __want out `target triple = "wasm32-unknown-wasi"` `wasm32 triple prepended` )
    = bad + bad ( __want out `define internal i32 @__nurl_pthread_create_stub(i8*, i8*, i8*, i8*)` `POSIX stub mirrors the declared signature` )
    = bad + bad ( __want out `ret i32 -1` `POSIX stub returns the error sentinel at the declared width` )
    = bad + bad ( __want_not out `declare i32 @__nurl_pthread_create_stub` `the stubbed declare is dropped` )
    = bad + bad ( __want_not out `__NURL_IR_AT_SENTINEL__A` `no masked-@ marker survives` )
    = bad + bad ( __want_not out `__NURL_IR_AT_SENTINEL__E` `no escape marker survives` )
    = bad + bad ( __want out `define i64 @__nurl_strlen_shim(i8* %a0)` `parameter attributes do not enter value types` )
    = bad + bad ( __want out `define i8* @__nurl_memcpy_shim(i8* %a0, i8* %a1, i64 %a2)` `copy shim preserves pointer arguments` )
    = bad + bad ( __want_not out `inttoptr i8* nocapture` `pointer contracts are not integers` )
    // Optional output is assembled by the external LLVM verifier control.
    ? > ( nurl_argc ) 1 { ( nurl_print ( string_data out ) ) } {}
    ( string_free out )

    ? > ( nurl_argc ) 1 { ^ bad } {}
    ? == bad 0 { ( nurl_print `PASS ir_test: string constants survive the wasm32 rewrite\n` ) ^ 0 } {}
    ^ 1
}
