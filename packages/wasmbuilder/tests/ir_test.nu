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
    // Real code, which SHOULD be rewritten.
    ( string_push_str ir `define i32 @main(i32 %argc, i8** %argv) {\n` )
    ( string_push_str ir `  %t = call i32 @pthread_create(i8* null, i8* null, i8* null, i8* null)\n` )
    ( string_push_str ir `  ret i32 0\n` )
    ( string_push_str ir `}\n` )

    : String out ( wb_prepare_ir_for_wasi ir )
    ( string_free ir )

    : ~ i bad 0
    = bad + bad ( __want out `[24 x i8] c"__NURL_IR_AT_SENTINEL__\00"` `sentinel-in-data survives byte for byte` )
    = bad + bad ( __want out `[22 x i8] c"define i32 @main(i32)\00"` `IR text in data is not retargeted` )
    = bad + bad ( __want out `define i32 @__main_argc_argv(i32 %argc, i8** %argv)` `real @main is retargeted` )
    = bad + bad ( __want out `target triple = "wasm32-unknown-wasi"` `wasm32 triple prepended` )
    = bad + bad ( __want out `define internal i32 @__nurl_pthread_create_stub(i8*, i8*, i8*, i8*)` `POSIX stub mirrors the declared signature` )
    = bad + bad ( __want out `ret i32 -1` `POSIX stub returns the error sentinel at the declared width` )
    = bad + bad ( __want_not out `declare i32 @__nurl_pthread_create_stub` `the stubbed declare is dropped` )
    = bad + bad ( __want_not out `__NURL_IR_AT_SENTINEL__A` `no masked-@ marker survives` )
    = bad + bad ( __want_not out `__NURL_IR_AT_SENTINEL__E` `no escape marker survives` )
    ( string_free out )

    ? == bad 0 { ( nurl_print `PASS ir_test: string constants survive the wasm32 rewrite\n` ) ^ 0 } {}
    ^ 1
}
