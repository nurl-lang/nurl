// diag_arm_tail_dangling_lit.nu — a surplus operand spilling into a
// statement-form arm's tail. '= fails + fails 1 1' inside a '? … { }'
// STATEMENT parsed as '= fails + fails 1' plus a bare literal '1' —
// which the dangling-operand check exempted as "the block's value",
// although the conditional's value is discarded. 110 of the mutation
// probe's extra-operand mutants compiled silently through exactly this
// hole. The literal is now recorded instead of exempted, the value
// joins (phi) consume the record, and a '?'/'??' statement that
// finishes void with the record still set dies pointing at the
// literal. A value-form conditional with literal arms stays legal
// (main's binding below).

: ~ i fails 0

@ check b ok → v {
    ? ! ok {
        ( nurl_print `FAIL\n` )
        = fails + fails 1 1
    } {}
}

@ main → i {
    : i x ? > fails 0 { 1 } { 2 }
    ( check F )
    ^ x
}
