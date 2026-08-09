// diag_call_enum_to_int_param.nu — passing an enum value where a
// numeric parameter is declared. The enum's tag is not a number
// without an explicit conversion: the emitted call used to pass the
// whole enum value ('call @f(%Color …)') where the callee reads a
// scalar register.
: | Color { Red Green Blue }

@ f i x → i {
    ^ x
}

@ main → i {
    : Color c Green
    ^ ( f c )
}
