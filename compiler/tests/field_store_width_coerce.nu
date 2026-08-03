// field_store_width_coerce.nu — `= . obj field expr` and the element
// store forms must width-coerce the RHS to the destination type
// (trunc / sext / zext by source signedness), the same store-time rule
// as `:` binds and struct-literal field inits. Found by the structural
// fuzzer (genprog): an i32 product stored into an i16 field emitted
// `store i16 %r  ; %r: i32` — invalid IR that only clang caught.

$ `stdlib/core/string.nu`

: P {
    i16 a
    u16 b
    i8 c
}

@ main → i {
    : P p @ P { 1 2 3 }
    // wider signed value into i16: trunc (70000 & 0xffff = 4464)
    = . p a * # i32 700 # i32 100
    ( nurl_print ( nurl_str_int # i . p a ) ) ( nurl_print `\n` )
    // wider unsigned into u16: trunc (0x1_86A0 → 0x86A0 = 34464, zext read)
    = . p b # u32 100000
    ( nurl_print ( nurl_str_int # i . p b ) ) ( nurl_print `\n` )
    // narrower unsigned into i8: 200 → -56 as i8
    = . p c # u 200
    ( nurl_print ( nurl_str_int # i . p c ) ) ( nurl_print `\n` )
    // element store through a slice of u16 from an i64 value
    : [u16 xs [u16 | 1 2 3]
    = . xs 1 70000
    : ~ i sum 0
    ~ x xs { = sum + sum # i x }
    ( nurl_print ( nurl_str_int sum ) ) ( nurl_print `\n` )
    ^ 0
}
