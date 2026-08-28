// struct_to_int_cast.nu — `#`-cast from a struct value to an integer.
//
// `# <int> someStruct` recovers field 0 of the struct, normalised to
// the destination integer type: a plain i64 field passes through, a
// narrow integer field is sign-extended, a pointer field is
// `ptrtoint`-ed. Companion to enum_to_int_cast.nu (where field 0 is the
// variant tag). Before this fix the cast emitted no instruction and
// the i64-typed use site failed the LLVM verifier.
//
// Expected output:
//   42
//   -3
//   123

: Point { i x i y }
: Tiny { i8 t }
: Handle { * i p }

@ main → v {
    // field 0 is a plain i64 — passes straight through
    : Point pt @ Point { 42 99 }
    ( nurl_println_int # i pt )  // 42

    // field 0 is i8 — sign-extends through the cast
    : Tiny tn @ Tiny { # i8 -3 }
    ( nurl_println_int # i tn )  // -3

    // field 0 is a pointer — round-trip struct → i64 → pointer
    : *i cell # *i ( malloc Z i )
    = . cell 0 123
    : Handle h @ Handle { cell }
    : i raw # i h
    : *i back # *i raw
    ( nurl_println_int . back 0 )  // 123
}
