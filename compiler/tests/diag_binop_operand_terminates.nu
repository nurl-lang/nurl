// diag_binop_operand_terminates.nu — a binary operator whose operand is
// a block that BREAKS.
//
// There are three spellings of "this operand has no value", and the
// binary-operator battery knew two: the literal `v` type, and the
// `undef` a void-returning call yields. A block that terminates —
// `{ ( string_free t ) break }`, or one ending in `^` or `continue` —
// hands back no register at all, the empty string. So `? == 3 { … }`,
// an `==` one operand short that swallowed the then-block, emitted
//
//     %r8 = icmp eq i64 3,
//
// with nothing after the comma, and clang answered `expected value
// token` on the NEXT line.
//
// Same arity trap as the other two, same cure, third spelling. Found by
// deleting one token from loop_break_continue.nu with the sweep's clang
// oracle on: the `k` in `? == k 3`.

$ `stdlib/core/string.nu`

@ main → i {
    : ~ i k 0
    ~ < k 100 {
        : String tmp ( string_from `xyz` )
        ? == 3 { ( string_free tmp ) break } {}
        ( string_free tmp )
        = k + k 1
    }
    ^ 0
}
