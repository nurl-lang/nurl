// should_fail_binop_width_mix.nu — two SSA registers of different
// integer widths as binary-operator operands must be rejected: the
// emitted instruction prints ONE type, so the narrower register was
// invalid IR (comparisons) or width-reinterpreted (shifts). Found by
// the structural fuzzer (24 build-fails in one 1000-seed campaign).

$ `stdlib/core/string.nu`

@ main → i {
    : i32 a # i32 70000
    : i b 5
    ? <= a b { ( nurl_print `no\n` ) } {}
    ^ 0
}
