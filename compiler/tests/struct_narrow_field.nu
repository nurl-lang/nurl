// struct_narrow_field.nu — integer-width coercion of struct fields at
// `@`-construction. An i64 value placed in a narrow (`i8`/`i16`/`i32`)
// field is truncated to the field width; a narrow value placed in a
// wider field is sign-extended. Neither needs an explicit `#`-cast any
// more — before this fix `@ S { -3 }` into an `i8` field emitted
// `insertvalue ... i64 -3` and failed the LLVM verifier.
//
// Expected output:
//   -3
//   1000
//   7
//   300
//   -5

: Mix { i8 a i16 b i32 c i wide }
: Wrap { i big }

@ main → v {
    // i64 literals land in narrow fields without explicit casts
    : Mix m @ Mix { -3 1000 7 300 }
    ( nurl_println_int # i . m a )  // -3   (i8, sign preserved)
    ( nurl_println_int # i . m b )  // 1000 (i16)
    ( nurl_println_int # i . m c )  // 7    (i32)
    ( nurl_println_int . m wide )  // 300  (i64, unchanged)

    // a narrow value sign-extends into a wider field
    : i8 sm # i8 -5
    : Wrap w @ Wrap { sm }
    ( nurl_println_int . w big )  // -5
}
