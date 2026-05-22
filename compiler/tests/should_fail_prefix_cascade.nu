// should_fail_prefix_cascade.nu — a ternary `? cond then else` whose
// else-arm is missing. NURL operators have fixed arity and no closing
// bracket, so the parser consumes the FOLLOWING statement as the
// else-arm; the error then surfaces on the innocent next line. The
// diagnostic names the offending token and points back at the line
// whose prefix operator is short an argument. Expect COMPILE FAIL.

@ pick i a → i { ^ + a 1 }

@ main → i {
    : i a ( pick 5 )
    : i b ? > a 0 a
    : i c ( pick a )
    ^ c
}
