// diag_generic_targ_deficit.nu — fewer type arguments than the
// generic declares. `opt_map [i]` (it takes [A B]) used to die later,
// deep inside instantiation, with an unrelated substitution error;
// the arity is checkable right at the call.
$ `stdlib/core/option.nu`

@ main → i {
    : ?i o @ ?i { T 7 }
    : ( @ i i ) sq \ i x → i { ^ * x x }
    : ?i m ( opt_map [i] o sq )
    ^ 0
}
