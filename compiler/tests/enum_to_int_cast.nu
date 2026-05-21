// enum_to_int_cast.nu — `#`-cast from an enum value to an integer.
//
// An enum value's LLVM layout is `{ i64, ... }` with field 0 holding
// the variant tag; casting the enum to any integer type recovers that
// tag. A narrower destination integer truncs the i64 tag down. Before
// this fix `# i someEnum` emitted no conversion and the i64-typed use
// site (return, print, arithmetic) failed the LLVM verifier.
//
// Expected output:
//   0
//   2
//   1
//   1

: | Col { Red  Grn  Blu }

// Wide enum: a payload-carrying variant still yields its tag.
: | Sig { Lo  Hi i }

@ main → v {
    : Col a Red
    ( nurl_print_int # i a )           // 0 — first variant

    : Col b Blu
    ( nurl_print_int # i b )           // 2 — third variant

    : Col c Grn
    ( nurl_print_int # i # i8 c )      // 1 — tag truncs to i8, widens back

    : Sig s @ Sig { Hi 7 }
    ( nurl_print_int # i s )           // 1 — wide-enum variant tag
}
