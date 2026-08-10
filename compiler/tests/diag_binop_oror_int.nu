// diag_binop_oror_int.nu — '||' with an integer on the left. '||' and
// '&&' are bool-only and short-circuit; '|' and '&' are the bitwise
// pair. The cure is to compare the integer, not to cast it.
@ main → i {
    : i n 3
    : b r || n T
    ? r { ^ 1 } {}
    ^ 0
}
