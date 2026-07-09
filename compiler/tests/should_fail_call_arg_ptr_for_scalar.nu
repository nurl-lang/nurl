// should_fail_call_arg_ptr_for_scalar.nu — the argument type checker must
// reject a pointer value (here a string literal, i8*) passed where a scalar
// `i` parameter is expected. Without the check `( add 1 `two` )` compiled to
// garbage (pointer arithmetic on the string's address) — the C1 hole.

@ add i a i b → i { ^ + a b }

@ main → i {
    : i x ( add 1 `two` )
    ^ 0
}
