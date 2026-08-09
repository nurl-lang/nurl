// diag_enum_arith.nu — arithmetic on an enum operand. `+ c 1` emitted
// `add %Color …` — invalid IR only clang saw; an enum is a closed set
// of named variants, not a number, and ordering/arithmetic have no
// meaning on it ('# i c' reads the tag intentionally).
: | Color { Red Green Blue }

@ main → i {
    : Color c Green
    ^ + c 1
}
