// diag_bind_value_is_return.nu — a binding whose initialiser is the `^`
// that was meant to be the function's return.
//
// `: i a` has no value of its own, so the `^ 0` below becomes its
// initialiser: the binding returns, and the function has no return left.
// That reading is correct and is what the diagnostic says. What was
// wrong was the IR on the way there — the `^` emitted the block's
// terminator and the statement then emitted its store AFTER it, in the
// same basic block. __handle_unreachable_stmt parks exactly those
// instructions in a fresh dead label, but it runs BETWEEN statements: it
// caught this shape when another statement followed and missed it when
// the binding was the block's last, leaving a block whose final
// instruction is a store. clang reported `expected instruction opcode`
// at the closing brace, with no source location.
//
// The legal spelling of the same thing — `: i x ^ a b`, which the
// `^`-vs-`^^` warning deliberately keeps compiling — now parks its dead
// store correctly too (see should_warn_caret_xor.nu, whose IR this
// change moved one block over and whose behaviour it did not).
//
// Found by the token-deletion sweep's clang oracle: deleting the `7`
// from `: Color c 7` produces exactly this.

@ main → i {
    : i a
    ^ 0
}
