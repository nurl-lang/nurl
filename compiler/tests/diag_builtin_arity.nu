// diag_builtin_arity.nu — the C-runtime surface the compiler
// pre-registers carried a RETURN type only, so nothing checked a call to
// it: arity, argument types, nothing. `( nurl_print )` emitted
// `call void @nurl_print()` against a declaration that takes one
// pointer. Under opaque pointers the call carries its own signature, so
// LLVM's verifier accepts it and the ABI mismatch reaches run time.
//
// The signatures were never missing — emit_header emits a `declare` for
// every one of these symbols. Reading the parameter list out of that
// line fills the same side-tables an '&'-declared symbol uses.

@ main → i {
    ( nurl_print )
    ^ 0
}
