// diag_binop_andand_int.nu — '&&' with an integer on the left, the
// sibling of diag_binop_oror_int.
@ main → i {
    : i n 3
    : b r && n T
    ? r { ^ 1 } {}
    ^ 0
}
