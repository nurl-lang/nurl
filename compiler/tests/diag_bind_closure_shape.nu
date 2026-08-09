// diag_bind_closure_shape.nu — binding a closure to a declaration with
// a DIFFERENT signature. Both sides are { ptr, ptr } at the store
// level, so this ASSEMBLED — and every later invoke through the
// declared type reinterpreted its arguments (': ( @ i )' promised a
// zero-param closure; calling it as one leaves x's slot unset).
@ main → i {
    : ( @ i ) f \ i x → i { ^ * x x }
    ^ 0
}
