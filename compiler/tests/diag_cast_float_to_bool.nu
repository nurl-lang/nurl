// diag_cast_float_to_bool.nu — '# b' of a float is not a truth
// test: an i1 holds only 0 or 1, so `fptosi double 3.5 to i1` is poison
// for any other value. The comparison must be written out.
@ main → i {
    : b z # b 3.5
    ^ 0
}
