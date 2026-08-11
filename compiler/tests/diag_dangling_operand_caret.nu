// diag_dangling_operand_caret.nu — a binary operator one operand short,
// which swallows the '^' that follows. The message has to explain the
// fixed-arity trap, since nothing in the source looks wrong locally.
@ main → i {
    : i n + 1
    ^ n
}
