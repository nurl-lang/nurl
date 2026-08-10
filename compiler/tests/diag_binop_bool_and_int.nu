// diag_binop_bool_and_int.nu — '&' sibling of diag_binop_bool_or_int.
// Both checks fire only after gen_expr has consumed the right operand,
// by which point the lexer sits on the NEXT statement — so they are
// anchored with die_stmt. Before that they printed a correct message
// against the wrong line, which for a model reading the output is
// worse than a vague message against the right one.
@ main → i {
    : b a T
    : i n 3
    : b r & a n
    ? r { ^ 1 } {}
    ^ 0
}
