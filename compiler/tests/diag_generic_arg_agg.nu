// diag_generic_arg_agg.nu — an option passed to a CONCRETE scalar
// parameter of a generic function. The direct-call battery is guarded
// with call_name == fname, so a generic instantiation skipped every
// argument check and `( pick [i] o 7 )` emitted
// `call @pick__i64({ i1, i64 } %o, i64 7)` — assembled, garbage. The
// battery now runs post-substitution for generic callees too.

@ pick [T] i n T x → T {
    ^ x
}

@ main → i {
    : ?i o @ ?i { T 5 }
    : i r ( pick [i] o 7 )
    ( nurl_print_int r )
    ^ 0
}
