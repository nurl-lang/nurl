// diag_generic_targ_surplus.nu — more type arguments than the generic
// declares. `vec_get [i i]` used to compile clean: the mangle used
// every arg, substitution used only the declared tparam, and the call
// resolved to a monomorph name no other site shares — silently saying
// something the user didn't mean.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    : ?i o ( vec_get [i i] v 0 )
    ( vec_free [i] v )
    ^ 0
}
