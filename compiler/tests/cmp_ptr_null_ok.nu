// cmp_ptr_null_ok.nu — the null-check shapes the operand check must
// keep accepting.
//
// The negative control for should_fail_cmp_ptr_int: extending the
// pointer/scalar check to ordering comparisons must not touch equality,
// which is how a null check is written, nor pointer-to-pointer
// ordering, which compares two addresses.
//
// Expected output:
//   null checks ok

@ main → i {
    : s p `x`
    : s q `y`
    : ~ i hits 0
    ? == p 0 { = hits + hits 1 } {}
    ? != p 0 { = hits + hits 1 } {}
    ? < p q { = hits + hits 1 } {}
    ? > p q { = hits + hits 1 } {}
    ( nurl_print `null checks ok\n` )
    ^ 0
}
