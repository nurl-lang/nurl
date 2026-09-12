// diag_cast_between_structs.nu — '#' from one named struct to another.
//
// Nothing above the final fallthrough in gen_cast converts an aggregate,
// so that path handed the operand register straight back wearing the
// TARGET's type. For two integer spellings of one width (`# u <i8>`) that
// is exactly right — the bits are the value. For a named struct it is not
// a conversion at all:
//
//     ret %Q %r1        ; %r1 is a %Pt
//
// clang: "'%r1' defined with type '%Pt = type { i64, i64 }' but expected
// '%Q = type { i64, i64, i64 }'" — about generated IR, with no NURL
// location. The two types do not even have the same number of fields.
//
// The anonymous-aggregate source is diagnosed a few lines above with the
// same reasoning and almost the same words. The named one reached the
// fallthrough because `%Struct` sources are handled far above ONLY when
// the destination is an integer.
: Pt { i x i y }
: Q { i a i b i c }

@ mk → Pt { ^ @ Pt { 1 2 } }

@ widen → Q { ^ # Q ( mk ) }

@ main → i {
    : Q q ( widen )
    ^ . q a
}
