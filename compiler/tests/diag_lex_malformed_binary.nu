// diag_lex_malformed_binary.nu — '0b' with no digits, the twin of
// diag_lex_malformed_hex.
@ main → i {
    : i n 0b
    ^ n
}
