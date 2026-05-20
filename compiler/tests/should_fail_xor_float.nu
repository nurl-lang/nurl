// should_fail_xor_float.nu — the `^^` XOR operator is integer/bool
// only. LLVM has no float `xor`, so applying `^^` to float operands
// is a compile error. Expect COMPILE FAIL.

@ main → i {
    : f x 1.5
    : f y 2.5
    : f z ^^ x y
    ^ 0
}
