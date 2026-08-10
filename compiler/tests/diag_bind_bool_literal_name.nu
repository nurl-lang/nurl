// diag_bind_bool_literal_name.nu — 'T' as a binding name. Models reach
// for T as a type variable, and in NURL it is the true literal.
@ main → i {
    : i T 5
    ^ T
}
