// diag_arg_void_value.nu — a VOID expression as a call argument. A '?'
// conditional whose arms have different types degrades to void
// (gen_cond's documented fallback), and the return boundary catches
// that — but an argument position used to slide through and emit
// `call @nurl_print(void undef, …)`: invalid IR only the LLVM
// verifier saw. Found by the mutation probe's extra-operand class:
// a surplus operand pushes the real argument out of the ternary and
// the arms stop agreeing. The argument law now rejects it at the
// call site, with the spill hint spelled out.

@ main → i {
    : i got 3
    : i want 3
    ( nurl_print ? == got want 1 ` ok ` ` no ` )
    ^ 0
}
