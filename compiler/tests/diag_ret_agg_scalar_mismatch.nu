// diag_ret_agg_scalar_mismatch.nu — an option returned from a function
// that declares a plain scalar. `{ i1, i64 }` beside `i64` matched no
// pairwise branch in ret_ty_agree (each asked about floats, pointers,
// two aggregates, named structs, or enums), so the `ret` was emitted
// with the value's own type — invalid IR only the LLVM verifier saw.
// The total-agreement backstop now rejects every such leftover pair.

@ f i x → i {
    : ?i o @ ?i { T x }
    ^ o
}

@ main → i {
    ( nurl_print_int ( f 3 ) )
    ^ 0
}
