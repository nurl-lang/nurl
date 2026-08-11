// diag_binop_void_call_operand.nu — a binary operator one operand short,
// which swallows the following statement.
//
// This was a silent miscompile. `+ n` needs a second operand, so it took
// the NEXT statement — a call returning 'v' — and gen_call gives a void
// call the value `undef`:
//
//     %r3 = add i64 %r2, undef
//
// nurlc printed that with status 0. The program compiled, linked, ran,
// and computed garbage while the swallowed call still happened, as a
// side effect of an addition.
//
// die_if_void could not see it: it tests the operand's VALUE against
// 'void', and a v-returning call's value is 'undef'. Widening that
// helper is wrong — an initialiser may legitimately take a '?' whose
// arms both return, which also yields undef (dead_store_both_arms_ret).
// Only a BINARY operator can never have a valueless operand, so the rule
// lives at that site alone.
@ side → v { ( nurl_print `SIDE\n` ) }

@ main → i {
    : ~ i n 1
    = n + n
    ( side )
    ^ 0
}
