// diag_ffi_variadic_missing_fixed.nu — a variadic call that omits a
// parameter the declaration does NOT make optional.
//
// '...' makes the TAIL optional, never the fixed prefix ahead of it.
// gen_ffi_decl registers no `__arity` for a variadic symbol — there is no
// single right count — so the call-site arity check skipped it entirely,
// including the minimum. `( xpf )` against `xpf s fmt ... → i` emitted
//
//     call i64 (i8*, ...) @xpf()
//
// which the LLVM verifier rejects ("not enough parameters specified for
// call"). Where such a call does assemble, the callee reads its fixed
// parameter out of an ABI register this call never set.
//
// The fixed count was already recorded, as `<fname>__variadic_fixed`, for
// the argument-promotion path. Nothing had ever asked it this question.
// The comment on the non-variadic registration says why the check exists
// — "a missing argument read an unset ABI register, silently" — and the
// variadic spelling has exactly the same hazard.
& `libc` @ xpf s fmt ... → i

@ main → i {
    : i r ( xpf )
    ( nurl_print `unreachable\n` )
    ^ r
}
