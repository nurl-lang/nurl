// diag_binop_bool_or_int.nu — '|' with a bool on the left and an
// integer on the right. '|' is bitwise-or on integers and or on bools,
// never a mix, and the n-ary shape ('| | a b c') is the thing a model
// reaches for when it wants three conditions.
@ main → i {
    : b a T
    : i n 3
    : b r | a n
    ? r { ^ 1 } {}
    ^ 0
}
