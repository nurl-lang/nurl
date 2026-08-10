// diag_lex_malformed_hex.nu — '0x' with no digits after it. A lexer
// diagnostic, so it is fail-fast (outside the per-declaration recovery
// frame) and prints exactly one error.
@ main → i {
    : i n 0x
    ^ n
}
