// should_warn_dead_value.nu — critic A2: the last silent prefix-arity
// cascade. A statement that produces a value without being a call or
// control flow (bare local identifier, operator expression, `#` cast,
// `.` field read) discards that value — under prefix notation this is
// exactly the residue a fixed-arity operator leaves behind when it is
// short an argument and swallows the next statement's leading token.
// The bare-LITERAL flavor has always been a hard error (dangling
// operand); these shapes name real bindings, so they warn.
//
// The golden locks BOTH directions: each dead statement below warns
// exactly once, and the legitimate tail-value shapes (a value-block's
// final expression, a `^` return operand) stay silent — the program
// still compiles, links, runs, and prints its expected output.

: Pt { i x i y }

@ main → i {
    : i a 5
    : Pt p @ Pt { 1 2 }

    // Dead bare identifier — the classic swallowed-remainder shape.
    a

    // Dead operator expression: computes a+1, discards it.
    + a 1

    // Dead cast.
    # i8 a

    // Dead field read.
    . p x

    // NOT warned: value-block tail — the block result feeds the binding.
    : i b ? > a 0 { + a 10 } { 0 }
    ( nurl_print_int b )

    // NOT warned: call statement (effects) and `^` return operand.
    ( nurl_print `ok\n` )
    ^ 0
}
