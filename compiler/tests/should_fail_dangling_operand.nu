// should_fail_dangling_operand.nu — dangling-operand-as-statement check.
//
// `& x 255 0x40` looks like it masks `(x & 255) & 0x40`, but `&` is a
// binary prefix operator: it consumes exactly two operands (`x` and
// `255`), so the trailing `0x40` is parsed as its own bare-literal
// expression statement whose value is discarded. The mask silently
// becomes `& x 255`. This is the classic prefix-arity foot-gun — and
// the exact bug that made the dmg-acid2 LYC STAT interrupt fire on
// every scanline (it was `& m 255 0x40` instead of `& & m 255 0x40`).
//
// Post-fix (gen_block_stmts / gen_block_ret dangling-operand check):
// a bare literal whose value is discarded (i.e. not the block's final
// return expression) is a COMPILE FAIL. A literal that IS the block's
// result, or a match-arm literal body, stays legal.
@ main → i {
    : i x 0xB1
    : i r & x 255 0x40
    ^ r
}
