// should_fail_cmp_ptr_int.nu — no ordering between an address and a
// number.
//
// The pointer/scalar operand check exempted ALL comparisons, for a
// reason that is only about equality: `== ptr 0` is a null check and
// ptr↔ptr compares in i64. Written as "comparisons", the exemption also
// covered '<' '>' '<=' '>=', where a pointer against an integer means
// nothing — so `? > 1 \`s\`` compiled clean and produced a running
// binary that silently compared an i64 with an address.
//
// Ordering comparisons are checked now. Equality keeps the exemption,
// which cmp_ptr_null_ok pins from the other side.
//
// Expected: COMPILE FAIL.

@ main → i {
    ? > 1 `s` { ^ 1 } {}
    ^ 0
}
