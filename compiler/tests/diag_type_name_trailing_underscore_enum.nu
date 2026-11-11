// diag_type_name_trailing_underscore_enum.nu — an enum's name does not end
// in `_`, as a struct's does not
// (diag_type_name_trailing_underscore_struct.nu): as a type argument,
// `( Vec Shade_ )` would be spelled `Vec__Shade_`, and a type holding it
// and another argument `Two__Shade___i64`.

: | Shade_ {
    Light
    Dark
}

@ main → i {
    : Shade_ s # Shade_ Light
    ^ ?? s {
        Light → 0
        Dark → 1
    }
}
