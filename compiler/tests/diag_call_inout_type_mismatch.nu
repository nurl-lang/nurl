// diag_call_inout_type_mismatch.nu — an 'inout' argument passes
// the binding's ADDRESS, so no register coercion is possible: the
// binding's type must equal the declared parameter type exactly. This
// used to emit `call void @bump(i64* …)` into `define void
// @bump(double* …)` — the callee stores a double's bits into the
// caller's integer slot, silently.
@ bump inout f x → v { = x + x 1.0 ^ }

@ main → i {
    : ~ i n 3
    ( bump n )
    ^ n
}
