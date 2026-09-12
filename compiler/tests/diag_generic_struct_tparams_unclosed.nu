// diag_generic_struct_tparams_unclosed.nu — a generic struct whose
// TYPE-PARAMETER list is never closed. The sibling
// diag_generic_struct_unclosed.nu is the missing body BRACE; this is the
// missing `]`, which the parser walks to and which used to take the rest
// of the declaration with it when it was not there.

: Box [T { T v i tag }

@ main → i {
    ^ 0
}
