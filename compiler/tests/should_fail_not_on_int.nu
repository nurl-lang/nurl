// '!' (logical not) requires a b operand. An i-typed binding — even one
// initialised with a bool literal (the T/F → i widening is legal) — must be
// rejected at the '!' use site, NOT emitted as 'xor i1 <i64 reg>' for clang
// to reject at the IR level (the pre-fix behaviour, found via the genacc
// generation corpus: haiku's words.nu wrote ': ~ i in_word F' then
// '? ! in_word').
@ main → i {
    : ~ i flag F
    ? ! flag {
        ( nurl_println_int 1 )
    } {
        ( nurl_println_int 2 )
    }
    ^ 0
}
