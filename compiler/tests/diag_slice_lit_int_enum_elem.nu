// diag_slice_lit_int_enum_elem.nu — a bare number as an element of an
// enum-typed slice literal. The store is emitted at the declared
// `%Color`, so `[Color | Red 7 Blue]` reached clang as `store %Color
// <i64>` — and no number converts into a closed set of named variants
// anyway.
: | Color { Red Green Blue }

@ main → i {
    : [Color cs [Color | Red 7 Blue]
    ^ 0
}
