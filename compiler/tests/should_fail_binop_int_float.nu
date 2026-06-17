// should_fail_binop_int_float.nu — mixing an int and a float in one operator.
// NURL has no implicit numeric conversions; `+ 1 1.0` used to emit
// `add i64 1, 1.0` that only clang rejected. gen_binary now rejects it.
@ main → i { : f x + 1 1.0  ^ 0 }
