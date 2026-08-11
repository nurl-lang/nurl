// diag_binop_agg_operand.nu — an aggregate value as a binary-operator
// operand. `= cnt + cnt` (one operand short) swallowed the following
// `??` expression, and the option it yields reached the `+` as
// `add i64 %r1, %r6` with %r6 a `{ i1, i64 }` — invalid IR that nurlc
// accepted (rc 0) and only the LLVM verifier rejected. The diagnostic
// names both facets: aggregates have no arithmetic, and the arity
// cascade that put one here.

: ~ i cnt 0

@ f i n → ?i {
    = cnt + cnt

    ?? n {
        0 → @ ?i { T 1 }
        _ → @ ?i { F }
    }
}

@ main → i {
    : ?i r ( f 0 )
    ^ 0
}
