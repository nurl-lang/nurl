// diag_agg_lit_too_many_values.nu — a surplus value in an ANONYMOUS
// aggregate literal. '@ ?i { T + n 2 2 }' (the '+' given one operand
// too many spills its surplus into a new "field") emitted an
// insertvalue past the option's last slot — "invalid indices for
// insertvalue" from the LLVM verifier, with no source location. The
// named-struct arity check keys on a registered field count anonymous
// shapes don't have; this is its anon twin.

@ f i n → ?i {
    ^ @ ?i { T + n 2 2 }
}

@ main → i {
    : ?i r ( f 1 )
    ^ 0
}
