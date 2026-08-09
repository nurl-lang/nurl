// diag_bind_agg_to_scalar.nu — binding an option value to a plain
// scalar declaration. Every legal unwrap ('??', '.  0/1' field access)
// is handled upstream, so what reached the store was
// 'store i64 { i1, i64 } …' — an aggregate into a scalar slot. The
// diagnostic points at '??' destructuring, not at a cast.
@ main → i {
    : ?i o @ ?i { T 7 }
    : i x o
    ^ x
}
