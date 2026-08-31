// diag_arg_agg_to_scalar.nu — an option passed where a NURL callee
// declares a plain scalar parameter. The per-argument battery asked
// about pointers, named types and closure pairs; an anonymous
// `{ i1, i64 }` beside a scalar `i64` matched none of them, so the
// call was emitted with the argument's own type — clang assembles it
// (the call carries its own function type under opaque pointers) and
// the callee reads whichever bytes the ABI put in the register. The
// anonymous-aggregate agreement check now rejects the pair at the
// call site.

@ g i x → i {
    ^ x
}

@ main → i {
    : ?i o @ ?i { T 5 }
    : i r ( g o )
    ( nurl_print_int r )
    ^ 0
}
