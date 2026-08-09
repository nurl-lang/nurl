// diag_ret_option_shape.nu — returning a '?f' value out of a '→ ?i'
// function. The two option aggregates are spelled '{ i1, double }' and
// '{ i1, i64 }': the ret was invalid IR that only the LLVM verifier
// saw, three build stages later. NURL has no implicit conversions
// between option/result/slice/closure shapes.
@ get → ?i {
    ^ @ ?f { T 1.5 }
}

@ main → i {
    : ?i o ( get )
    ^ 0
}
