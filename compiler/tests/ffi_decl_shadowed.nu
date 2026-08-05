// ffi_decl_shadowed — a NURL @-function may DEFINE a symbol that an FFI
// declaration names.
//
// This is how a program supplies its own version of something the
// runtime would otherwise provide, and it is the shape the unikernel's
// socket shims take: `nurl_tcp_*` is a C symbol in the hosted runtime
// and pure NURL over the sans-IO stack in stdlib/net/ when there is no
// operating system underneath.
//
// nurlc used to emit BOTH `declare i64 @name(...)` (from the FFI
// declaration) and `define i64 @name(...)` (from the @-function), which
// LLVM rejects as "invalid redefinition of function". The program was
// well-formed NURL; the error came out of clang, pointing at generated
// code, which is the worst place a diagnostic can appear. A definition
// now suppresses the declaration, exactly as it does in C.
$ `stdlib/core/io.nu`

// Declared as an external C symbol…
& `c` @ nurl_test_shadowed_fn i x → i

// …and defined here instead. The definition wins.
@ nurl_test_shadowed_fn i x → i {
    ^ + * x 10 7
}

// A second one, to show the suppression is per-symbol rather than a
// global switch: this one is declared and NOT defined, so its declare
// must survive. `strlen` is a real libc symbol, so the link proves it.
& `c` @ strlen s p → i

@ main → i {
    ( nurl_print `shadowed(4)=` )
    ( nurl_print ( nurl_str_int ( nurl_test_shadowed_fn 4 ) ) )
    ( nurl_print `\n` )
    ( nurl_print `strlen(hello)=` )
    ( nurl_print ( nurl_str_int ( strlen `hello` ) ) )
    ( nurl_print `\n` )
    ^ 0
}
