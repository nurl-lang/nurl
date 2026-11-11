// diag_type_name_instance_spelling_enum.nu — an enum's name holds no `__`
// past its leading underscores, as a struct's does not
// (diag_type_name_instance_spelling_struct.nu): `Vec__Shade` is how the
// compiler spells `( Vec Shade )`.

: | Vec__Shade {
    Light
    Dark
}

@ main → i {
    : Vec__Shade s # Vec__Shade Light
    ^ ?? s {
        Light → 0
        Dark → 1
    }
}
