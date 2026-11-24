// diag_private_type_as_type_argument.nu — AGORA-861: a strict module's
// private type named as a TYPE ARGUMENT in another file is refused, as the
// bare name is. Before, `( Vec Impl )` and `( vec_new [Impl] )` took the
// name as one token and never asked whether it was visible, so a module
// could not keep a type private from code that wrapped it in a generic.
// Each form is refused at its own column, in this file.
$ `compiler/tests/private_handle_payload_mod.nu`
$ `stdlib/core/vec.nu`

// a generic type's argument
@ in_type → i {
    : ( Vec Impl ) q ( vec_new [i] )
    ^ 0
}

// a call's type argument
@ in_call → i {
    ^ ( vec_len [Impl] ( vec_new [Impl] ) )
}

// an option of it, inside a call's type argument
@ in_prefix → i {
    : i n ( vec_len [? Impl] ( vec_new [? Impl] ) )
    ^ n
}

@ main → i { ^ + + ( in_type ) ( in_call ) ( in_prefix ) }
