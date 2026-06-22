// should_fail_binop_bool_int.nu — an operator with one bool (i1) and one
// non-bool operand, both non-constant, used to emit a width-mismatched
// `icmp i1 %f, %n`. A literal operand (e.g. `== flag 0`) stays valid; two
// disagreeing registers are rejected.
@ main → i { : b f T : i n 5 : b r < f n ^ 0 }
