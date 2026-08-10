// diag_slice_elem_int_for_float.nu — integer literals in a float slice.
// The cure is the spelling ('2.0', not '2'), which the message shows.
@ main → i {
    : [f xs [f | 1 2 3]
    ^ 0
}
