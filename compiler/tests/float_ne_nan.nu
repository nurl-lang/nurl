// float_ne_nan.nu — float `!=` must follow IEEE 754: `x != y` is TRUE when
// either operand is NaN. The compiler emitted `fcmp one` (ORDERED not-equal),
// which is false for NaN operands, so `NaN != NaN` was false and the canonical
// NaN check `x != x` never detected a NaN. Fixed to `fcmp une` (matches C's
// `!=`; identical to `one` for non-NaN). `==` stays `fcmp oeq` (NaN == NaN is
// false, as IEEE requires).
@ prb s l b v → v { ( nurl_print l ) ( nurl_print `=` ) ( nurl_print ? v `true` `false` ) ( nurl_print `\n` ) }

@ main → i {
    : f nan / 0.0 0.0
    : f x 5.0
    ( prb `nan_ne_nan` != nan nan )  // true  (IEEE)
    ( prb `nan_eq_nan` == nan nan )  // false
    ( prb `nan_ne_x` != nan x )  // true
    ( prb `x_ne_x` != x x )  // false (x is not NaN)
    ( prb `x_ne_3` != x 3.0 )  // true
    ( prb `x_eq_x` == x x )  // true
    ^ 0
}
