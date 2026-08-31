// diag_trait_arg_agg.nu — an option passed to a trait method's 'i'
// parameter. Static trait dispatch resolves the impl and emits the
// mangled call directly, bypassing the direct-call battery — so
// `( show p o )` emitted `call @show__P(%P …, { i1, i64 } …)`:
// assembled, garbage. The impl scan now records the parameter roster
// and the dispatch site checks the assembled argstr against it.

: P { i a }

% Show { @ show P p i x → i }

% Show ( P ) { @ show P p i x → i { ^ x } }

@ main → i {
    : P p @ P { 1 }
    : ?i o @ ?i { T 5 }
    : i r ( show p o )
    ( nurl_print_int r )
    ^ 0
}
