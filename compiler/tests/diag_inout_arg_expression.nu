// diag_inout_arg_expression.nu — an expression at an inout parameter.
// The callee writes through the argument, so a temporary has nowhere to
// write back to.
@ bump inout i x → v { = x + x 1 }

@ main → i {
    : ~ i n 5
    ( bump + n 1 )
    ^ n
}
