// diag_binop_operand_returns.nu — a binary operator whose operand is a
// block that RETURNS.
//
// The sibling of diag_binop_operand_terminates.nu, and the harder half.
// A block ending in `break` hands back no register and is caught by the
// empty-operand rule; a block ending in `^` hands back the register the
// `^` returned, while the recorded TYPE stays the operator's. So
// `? != ( nurl_str_eq name `a` ) { ^ ( string_from … ) }` — a `!=` one
// operand short, swallowing the then-block — emitted
// `icmp ne i64 %r2, %r4` with %r4 a `%String`, and the
// aggregate-operand rule never saw an aggregate.
//
// Control being dead AFTER the operands when it was live before is the
// exact tell, and it means the operator cannot run at all. Found by
// deleting the `0` from `? != 0 ( … )`, which is what puts a block in
// operand position in the first place.

$ `stdlib/core/string.nu`

@ idx_for s name → String {
    ? != ( nurl_str_eq name `a` ) {
        ^ ( string_from `x` )
    } {}
    ? != 0 ( nurl_str_eq name `b` ) {
        ^ ( string_from `y` )
    } {}
    ^ ( string_from `z` )
}

@ main → i {
    : String s ( idx_for `a` )
    ( string_free s )
    ^ 0
}
