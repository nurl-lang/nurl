// should_fail_binop_ptr_int.nu — arithmetic mixing a string/pointer and an
// integer (`+ `a` 1`). Operator-level pointer arithmetic is unsupported and
// used to emit `add i64 i8* …`. gen_binary now rejects it.
@ main → i { : s x + `a` 1 ^ 0 }
