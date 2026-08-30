// diag_nested_field_path.nu — the two diagnostics of the nested field
// store `= . . o a b v`.
//
// `gen_nested_lvalue_addr` counts the leading dots and then walks that
// many field names. Two things can go wrong on that walk, and neither
// message had a test behind it (tools/check_diag_coverage.sh listed both
// as "no test makes the compiler print this"):
//
//   * the walk runs out of identifiers — what follows a hop is the VALUE,
//     not the field name the dot count promised;
//   * a hop names a field the struct does not have.
//
// The first needs THREE dots to reach: with two, the single remaining hop
// is the one `__nested_lvalue_ok` already proved is an identifier, so the
// check inside the loop can only fire from the second hop onwards.
//
// One function per diagnostic — a `die` stops its declaration, so two
// errors in one body would report only the first.

: Inner { i a i b }
: Mid { Inner in i m }
: Outer { Mid mid i n }

@ short_path → v {
    : ~ Outer o @ Outer { @ Mid { @ Inner { 1 2 } 3 } 4 }
    // Three dots promise three field names; the second hop is a string.
    = . . . o mid `x` b 7
}

@ no_such_field → v {
    : ~ Outer o @ Outer { @ Mid { @ Inner { 1 2 } 3 } 4 }
    = . . o nope n 7
}

@ main → i {
    ( short_path )
    ( no_such_field )
    ^ 0
}
