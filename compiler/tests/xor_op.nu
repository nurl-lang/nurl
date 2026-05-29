// xor_op.nu — the native `^^` XOR operator.
// `^^` is NURL's bitwise / logical exclusive-or, lexed as a single
// token (two adjacent carets) and lowered to LLVM `xor`. On integers
// it is bitwise XOR; on `b` values it is logical XOR. `^` alone
// remains the return operator — `^^` is a distinct token.

// Bitwise XOR on integers, and the pre-`^^` identity it replaces:
//   a XOR b == (a | b) - (a & b)
@ xor_identity i a i b → i {
    ^ - | a b & a b
}

@ main → i {
    : i a 12  // 1100
    : i b 10  // 1010
    ( nurl_print `xor=` ) ( nurl_print ( nurl_str_int ^^ a b ) ) ( nurl_print `\n` )  // 6
    ( nurl_print `id=` ) ( nurl_print ( nurl_str_int ( xor_identity a b ) ) ) ( nurl_print `\n` )  // 6
    ( nurl_print `self=` ) ( nurl_print ( nurl_str_int ^^ a a ) ) ( nurl_print `\n` )  // 0
    ( nurl_print `zero=` ) ( nurl_print ( nurl_str_int ^^ b 0 ) ) ( nurl_print `\n` )  // 10

    // Prefix nesting: ^^ ^^ 1 2 4  ==  (1 XOR 2) XOR 4  ==  7
    ( nurl_print `nest=` ) ( nurl_print ( nurl_str_int ^^ ^^ 1 2 4 ) ) ( nurl_print `\n` )

    // Logical XOR on b values.
    : b t T
    : b f F
    ( nurl_print `TF=` ) ( nurl_print ? ^^ t f `1` `0` ) ( nurl_print `\n` )  // 1
    ( nurl_print `TT=` ) ( nurl_print ? ^^ t t `1` `0` ) ( nurl_print `\n` )  // 0
    ( nurl_print `FF=` ) ( nurl_print ? ^^ f f `1` `0` ) ( nurl_print `\n` )  // 0

    // `^` is still RETURN, not XOR — this returns 0.
    ^ 0
}
