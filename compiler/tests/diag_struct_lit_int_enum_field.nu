// diag_struct_lit_int_enum_field.nu — a bare number in the position of
// an enum-typed struct field. `@ S { 7 }` emitted `insertvalue %S …,
// i64 7` against the `%Color` slot — invalid IR only clang reported;
// and no number converts into a closed set of named variants anyway.
: | Color { Red Green Blue }
: S { Color c }

@ main → i {
    : S s @ S { 7 }
    ^ 0
}
