// diag_match_mixed_arms.nu — a `??` expression whose arms are GENUINELY
// incompatible is not an expression, and pretending otherwise printed
// pointers.
//
// Integer arms of different widths are NOT this case any more: they unify
// losslessly at the join (each arm extended by its own signedness), the same
// bridging every store site already does — see match_arm_width_unify.nu for
// the positive side. What cannot unify is a float beside an integer: NURL has
// no implicit int↔float conversion anywhere, and inventing one at the join
// would make `?? m { T x → x F → 0.5 }` quietly round somebody's number.
//
// Such a `??` used to degrade SILENTLY to a statement and hand `undef` to the
// enclosing cast / binding — the program printed whatever was in the register.
// Both consumers now refuse a valueless operand, and the message says WHY the
// value is missing.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec f ) d ( vec_new [f] )
    ( vec_push [f] d 1.5 )
    // the cast consumer: '# i' over mixed f/i arms
    : i lo # i ?? ( vec_get [f] d 0 ) { T x → x F → 0 }
    // the binding consumer, no cast
    : i lo2 ?? ( vec_get [f] d 0 ) { T x → x F → 0 }
    ( vec_free [f] d )
    ^ + lo lo2
}
