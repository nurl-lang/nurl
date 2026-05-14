// Regression test — negative integer and float literals.
//
// '-' immediately followed by a digit lexes as a single negative number
// token. Binary MINUS still works as before (whitespace between '-' and
// its operand).

@ show_i i n → v { ( nurl_print_int n ) }

@ show_f f x → v { ( nurl_print ( nurl_str_float x ) ) }

@ main → i {
    // Direct negative integer literal
    ( show_i -1 )  // -1
    ( show_i -42 )  // -42
    ( show_i 0 )  //  0

    // Negative in variable binding (inference picks i)
    : i a -7
    ( show_i a )  // -7

    // Arithmetic with negative literals
    ( show_i + -3 5 )  //  2
    ( show_i - 10 -5 )  // 15   (10 - (-5))
    ( show_i * -4 3 )  // -12

    // Binary minus still works (whitespace preserves operator)
    ( show_i - 3 8 )  // -5

    // Negative float literal
    ( show_f -3.25 )  // -3.25
    ( show_f -1.5e2 )  // -150.0

    ^ 0
}
