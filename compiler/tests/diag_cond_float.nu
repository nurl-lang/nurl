// diag_cond_float.nu — a float condition. NURL conditions are
// 'b' or an integer tested non-zero; a float has no truth value (and
// NaN would make any implicit zero-test lie). Blindly narrowing used to
// emit `icmp ne double %r, 0` — invalid IR only clang reported, with a
// .ll line and no source location.
@ main → i {
    : f y 1.5
    ? y { ^ 1 } {}
    ^ 0
}
