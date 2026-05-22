// should_fail_paren_operator.nu — a parenthesised operator expression.
//
// '(' is function-call syntax; an operator token immediately after it
// means an operator expression was wrongly wrapped in parentheses.
// Here `( . p x )` should be the bare member access `. p x`. gen_call
// rejects it at the call site — before, the operator's lexeme became a
// call to a function literally named '.' and the failure surfaced far
// from the source at link time as `use of undefined value`.
//
// Expect COMPILE FAIL.

: Point { i x i y }

@ main → i {
    : Point p @ Point { 3 4 }
    : i v ( . p x )
    ^ v
}
