// should_fail_undef_ident.nu — a value-position reference to an
// identifier that is not in scope must be REJECTED by the front-end.
//
// This is the exact case from critic.md §4: the external reviewer
// compiled `: i x ^ a b c` and observed that nurlc emitted the
// `^`/`^^` warning but then EXITED 0 and produced invalid LLVM IR
// (`ret i64 %a`, an undefined SSA value) that only clang rejected —
// directly contradicting GOTCHAS.md's "every trap is a compiler
// diagnostic" claim.
//
// Root cause: gen_ident's bare `( nurl_str_cat `%` name )` fallback
// fired for ANY name that was neither a `__ptr` binding, a `__global`,
// nor a bare @-fn — including names that simply don't exist. The fix
// requires the fallback name to be a by-value parameter (`__param`)
// and otherwise dies with "use of undefined identifier". Expect
// COMPILE FAIL.

@ main → i {
    : i x ^ a b c
    ^ 0
}
