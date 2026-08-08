// diag_slice_lit_float_elem.nu — slice-literal elements are
// stored with the DECLARED element type, so a float element in an
// integer slice used to become `store i64 2.5, …` — invalid IR that
// nurlc accepted (rc 0) and only clang rejected, with a .ll line number
// and no source location.
@ main → i {
    : [i xs [i | 1 2.5 3]
    ^ 0
}
