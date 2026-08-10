// diag_int_lit_width_range.nu — a literal too large for the narrow
// operand it is combined with.
//
// The message used to report the accepted window as "that type holds
// -128..255", which is false of 'i8': i8 holds -128..127. The window is
// the signed range UNION the unsigned one, because the check does not
// read the operand's signedness — so it is a fact about eight bits, not
// about i8. Stating it as the type's range taught a model a rule the
// language does not have. The semantics are unchanged; only the claim is.
@ main → i {
    : i8 n 5
    : i8 r + n 9999
    ^ 0
}
