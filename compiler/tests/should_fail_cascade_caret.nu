// should_fail_cascade_caret.nu — the within-statement prefix-arity
// cascade that previously produced structurally-valid-but-WRONG IR.
//
// `: i x + 1` is short one operand for the binary `+`. With fixed prefix
// arity and no closing bracket, `+` silently consumes the next token —
// the `^` of the following `^ a` — parsing the statement as `+ 1 (^ a)`.
// nurlc used to emit `ret i64 %a` (the `^ a`) FOLLOWED by a dead
// `add i64 1, %a`: the function returned `a` immediately and the binding
// `x` was never computed, with exit status 0 (silent miscompile).
//
// gen_ret now refuses to emit a `ret` while parsing a value operand
// (g_ret_forbidden, set by gen_operand around every operator / call /
// condition / scrutinee / return-value sub-parse and reset by the
// control-flow arms that ARE legal `^` positions). The `^` is rejected
// on its own line with a cascade diagnostic. Expect COMPILE FAIL.

@ f i a → i {
    : i x + 1
    ^ a
}

@ main → i { ^ ( f 7 ) }
