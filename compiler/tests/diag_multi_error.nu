// diag_multi_error.nu — multi-error reporting: one nurlc run must report
// EVERY failing declaration (not stop at the first), then the summary
// line. Three independent errors in three functions; the golden pins all
// three diagnostics, their locations, and the "aborting due to 3
// previous errors" tail. Regression for the per-declaration recovery
// frame (die → resync → continue).

@ f1 → i {
    : i x `oops`
    ^ x
}

@ f2 → i {
    ^ ( no_such_fn 1 )
}

@ f3 → i {
    : i y 1.5
    ^ y
}

@ main → i {
    ^ + ( f1 ) + ( f2 ) ( f3 )
}
