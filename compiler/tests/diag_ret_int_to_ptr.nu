// diag_ret_int_to_ptr.nu — returning an integer where the declared
// return type is a pointer/string. Used to lower `ret i64 %n` out of a
// `define i8*` function — invalid IR that nurlc accepted (rc 0) and
// only the LLVM verifier rejected, with a .ll line number and no
// source location. The old `^ 0` null-idiom carve-out protected IR
// that was itself invalid, so nothing legal is lost; the diagnostic
// names the '# T 0' null spelling as the cure.
@ f i n → s {
    ^ n
}

@ main → i {
    : s x ( f 3 )
    ^ 0
}
