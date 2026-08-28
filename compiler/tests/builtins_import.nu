// builtins_import.nu — stdlib/core/builtins.nu (the documentation
// module for the compiler's pre-registered C-runtime surface) must be
// importable: every `& `c` @` line in it redeclares a symbol whose
// `declare` the emitted preamble already carries, and the compiler
// must skip the duplicate declare (LLVM rejects redefinitions) while
// keeping the call path working. Exercises one symbol per declare
// shape: s→v, f→s, (s,i,i)→i, ()→s, b→v, i32-typed libc.
//
// Determinism: pure computation + stdout, no clock/socket/env.

$ `stdlib/core/builtins.nu`

@ main → i {
    ( nurl_println ( nurl_str_float 2.5 ) )
    ( nurl_println ( nurl_str_int -42 ) )
    ( nurl_println_int ( nurl_count_byte `abcabc` 6 97 ) )
    ( nurl_println_int ( nurl_byte_substr `hello world` 11 `world` 5 ) )
    ( nurl_println ? F `true` `false` )
    ( nurl_println_int # i ( strcmp `same` `same` ) )
    ( nurl_println_int ( nurl_is_nan 1.5 ) )
    ^ 0
}
