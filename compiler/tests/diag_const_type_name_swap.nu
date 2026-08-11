// diag_const_type_name_swap.nu — a top-level declaration with the type
// and name swapped (': PI_FIXED i 314' for ': i PI_FIXED 314'). Used to
// emit '@i = global %PI_FIXED zeroinitializer' — an undefined named
// type only the LLVM verifier rejected, far from the source. With a
// type keyword sitting in the name slot the intent is unambiguous, so
// the diagnostic names the swap and spells the corrected declaration.

: PI_FIXED i 314

@ main → i {
    ^ 0
}
