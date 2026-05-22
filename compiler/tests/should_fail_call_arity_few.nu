// should_fail_call_arity_few.nu — a call supplying FEWER arguments
// than the callee declares. scan_fn_sigs records every non-generic
// @-function's parameter count; gen_call rejects an arg-count
// mismatch with a precise diagnostic at the call site instead of
// emitting a malformed `call` the LLVM verifier complains about
// far from the source. Expect COMPILE FAIL.

@ add i x i y → i { ^ + x y }

@ main → i {
    : i r ( add 3 )
    ^ r
}
